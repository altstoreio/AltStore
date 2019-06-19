//
//  AuthenticationOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltSign

enum AuthenticationError: LocalizedError
{
    case noTeam
    case noCertificate
    
    case missingPrivateKey
    case missingCertificate
    
    var errorDescription: String? {
        switch self {
        case .noTeam: return NSLocalizedString("Developer team could not be found.", comment: "")
        case .noCertificate: return NSLocalizedString("Developer certificate could not be found.", comment: "")
        case .missingPrivateKey: return NSLocalizedString("The certificate's private key could not be found.", comment: "")
        case .missingCertificate: return NSLocalizedString("The certificate could not be found.", comment: "")
        }
    }
}

@objc(AuthenticationOperation)
class AuthenticationOperation: ResultOperation<ALTSigner>
{
    private weak var presentingViewController: UIViewController?
    
    private lazy var navigationController = UINavigationController()
    private lazy var storyboard = UIStoryboard(name: "Authentication", bundle: nil)
    
    private var appleIDPassword: String?
    
    init(presentingViewController: UIViewController?)
    {
        self.presentingViewController = presentingViewController
        
        super.init()
        
        self.progress.totalUnitCount = 3
    }
    
    override func main()
    {
        super.main()
        
        // Sign In
        self.signIn { (result) in
            guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
            
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let account):
                self.progress.completedUnitCount += 1
                
                // Fetch Team
                self.fetchTeam(for: account) { (result) in
                    guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
                    
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success(let team):
                        self.progress.completedUnitCount += 1
                        
                        // Fetch Certificate
                        self.fetchCertificate(for: team) { (result) in
                            guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
                            
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success(let certificate):
                                self.progress.completedUnitCount += 1
                                
                                let signer = ALTSigner(team: team, certificate: certificate)
                                self.finish(.success(signer))
                            }
                        }
                    }
                }
            }
        }
    }
    
    override func finish(_ result: Result<ALTSigner, Error>)
    {
        guard !self.isFinished else { return }
        
        print("Finished authenticating with result:", result)
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.performAndWait {
            do
            {
                let signer = try result.get()
                let altAccount = signer.team.account
                
                // Account
                let account = Account(altAccount, context: context)
                account.isActiveAccount = true
                
                let otherAccountsFetchRequest = Account.fetchRequest() as NSFetchRequest<Account>
                otherAccountsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Account.identifier), account.identifier)
                
                let otherAccounts = try context.fetch(otherAccountsFetchRequest)
                for account in otherAccounts
                {
                    account.isActiveAccount = false
                }
                
                // Team
                let team = Team(signer.team, account: account, context: context)
                team.isActiveTeam = true
                
                let otherTeamsFetchRequest = Team.fetchRequest() as NSFetchRequest<Team>
                otherTeamsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Team.identifier), team.identifier)
                
                let otherTeams = try context.fetch(otherTeamsFetchRequest)
                for team in otherTeams
                {
                    team.isActiveTeam = false
                }
                
                // Save
                try context.save()
                
                // Update keychain
                Keychain.shared.appleIDEmailAddress = altAccount.appleID // "account" may have nil appleID since we just saved.
                Keychain.shared.appleIDPassword = self.appleIDPassword
                
                Keychain.shared.signingCertificateSerialNumber = signer.certificate.serialNumber
                Keychain.shared.signingCertificatePrivateKey = signer.certificate.privateKey
                
                super.finish(.success(signer))
            }
            catch
            {
                super.finish(.failure(error))
            }
            
            DispatchQueue.main.async {
                self.navigationController.dismiss(animated: true, completion: nil)
            }
        }
    }
}

private extension AuthenticationOperation
{
    func present(_ viewController: UIViewController) -> Bool
    {
        guard let presentingViewController = self.presentingViewController else { return false }
        
        self.navigationController.view.tintColor = .altPurple
        
        if self.navigationController.viewControllers.isEmpty
        {
            guard presentingViewController.presentedViewController == nil else { return false }
            
            self.navigationController.setViewControllers([viewController], animated: false)            
            presentingViewController.present(self.navigationController, animated: true, completion: nil)
        }
        else
        {
            viewController.navigationItem.leftBarButtonItem = nil
            self.navigationController.pushViewController(viewController, animated: true)
        }
        
        return true
    }
}

private extension AuthenticationOperation
{
    func signIn(completionHandler: @escaping (Result<ALTAccount, Swift.Error>) -> Void)
    {
        func authenticate()
        {
            DispatchQueue.main.async {
                let authenticationViewController = self.storyboard.instantiateViewController(withIdentifier: "authenticationViewController") as! AuthenticationViewController
                authenticationViewController.authenticationHandler = { (result) in
                    if let (account, password) = result
                    {
                        self.appleIDPassword = password
                        
                        completionHandler(.success(account))
                    }
                    else
                    {
                        completionHandler(.failure(OperationError.cancelled))
                    }
                }
                
                if !self.present(authenticationViewController)
                {
                    completionHandler(.failure(OperationError.notAuthenticated))
                }
            }
        }
        
        if let appleID = Keychain.shared.appleIDEmailAddress, let password = Keychain.shared.appleIDPassword
        {
            ALTAppleAPI.shared.authenticate(appleID: appleID, password: password) { (account, error) in
                do
                {
                    self.appleIDPassword = password
                    
                    let account = try Result(account, error).get()
                    completionHandler(.success(account))
                }
                catch ALTAppleAPIError.incorrectCredentials
                {
                    authenticate()
                }
                catch ALTAppleAPIError.appSpecificPasswordRequired
                {
                    authenticate()
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
        else
        {
            authenticate()
        }
    }
    
    func fetchTeam(for account: ALTAccount, completionHandler: @escaping (Result<ALTTeam, Swift.Error>) -> Void)
    {
        func selectTeam(from teams: [ALTTeam])
        {
            DispatchQueue.main.async {
                let selectTeamViewController = self.storyboard.instantiateViewController(withIdentifier: "selectTeamViewController") as! SelectTeamViewController
                selectTeamViewController.teams = teams
                selectTeamViewController.selectionHandler = { (team) in
                    if let team = team
                    {
                        completionHandler(.success(team))
                    }
                    else
                    {
                        completionHandler(.failure(OperationError.cancelled))
                    }
                }
                
                if !self.present(selectTeamViewController)
                {
                    completionHandler(.failure(AuthenticationError.noTeam))
                }
            }
        }
        
        ALTAppleAPI.shared.fetchTeams(for: account) { (teams, error) in
            switch Result(teams, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let teams):
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    if let activeTeam = DatabaseManager.shared.activeTeam(in: context), let altTeam = teams.first(where: { $0.identifier == activeTeam.identifier })
                    {
                        completionHandler(.success(altTeam))
                    }
                    else
                    {
                        selectTeam(from: teams)
                    }
                }
            }
        }
    }
    
    func fetchCertificate(for team: ALTTeam, completionHandler: @escaping (Result<ALTCertificate, Swift.Error>) -> Void)
    {
        func requestCertificate()
        {
            let machineName = "AltStore - " + UIDevice.current.name
            ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team) { (certificate, error) in
                do
                {
                    let certificate = try Result(certificate, error).get()
                    guard let privateKey = certificate.privateKey else { throw AuthenticationError.missingPrivateKey }
                    
                    ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
                        do
                        {
                            let certificates = try Result(certificates, error).get()
                            
                            guard let certificate = certificates.first(where: { $0.serialNumber == certificate.serialNumber }) else {
                                throw AuthenticationError.missingCertificate
                            }
                            
                            certificate.privateKey = privateKey
                            completionHandler(.success(certificate))
                        }
                        catch
                        {
                            completionHandler(.failure(error))
                        }
                    }
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
        
        func replaceCertificate(from certificates: [ALTCertificate])
        {
            DispatchQueue.main.async {
                let replaceCertificateViewController = self.storyboard.instantiateViewController(withIdentifier: "replaceCertificateViewController") as! ReplaceCertificateViewController
                replaceCertificateViewController.team = team
                replaceCertificateViewController.certificates = certificates
                replaceCertificateViewController.replacementHandler = { (certificate) in
                    if certificate != nil
                    {
                        requestCertificate()
                    }
                    else
                    {
                        completionHandler(.failure(OperationError.cancelled))
                    }
                }
                
                if !self.present(replaceCertificateViewController)
                {
                    completionHandler(.failure(AuthenticationError.noCertificate))
                }
            }
        }
        
        ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                if
                    let serialNumber = Keychain.shared.signingCertificateSerialNumber,
                    let privateKey = Keychain.shared.signingCertificatePrivateKey,
                    let certificate = certificates.first(where: { $0.serialNumber == serialNumber })
                {
                    certificate.privateKey = privateKey
                    completionHandler(.success(certificate))
                }
                else if certificates.isEmpty
                {
                    requestCertificate()
                }
                else
                {
                    replaceCertificate(from: certificates)
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
}
