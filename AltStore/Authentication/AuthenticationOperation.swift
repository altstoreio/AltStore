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

extension AuthenticationOperation
{
    enum Error: LocalizedError
    {
        case cancelled
        
        case notAuthenticated
        case noTeam
        case noCertificate
        
        case missingPrivateKey
        case missingCertificate
        
        var errorDescription: String? {
            switch self {
            case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
            case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
            case .noTeam: return NSLocalizedString("Developer team could not be found.", comment: "")
            case .noCertificate: return NSLocalizedString("Developer certificate could not be found.", comment: "")
            case .missingPrivateKey: return NSLocalizedString("The certificate's private key could not be found.", comment: "")
            case .missingCertificate: return NSLocalizedString("The certificate could not be found.", comment: "")
            }
        }
    }
}

class AuthenticationOperation: RSTOperation
{
    var resultHandler: ((Result<(ALTTeam, ALTCertificate), Swift.Error>) -> Void)?
    
    private weak var presentingViewController: UIViewController?
    
    private lazy var navigationController = UINavigationController()
    private lazy var storyboard = UIStoryboard(name: "Authentication", bundle: nil)
    
    private var appleIDPassword: String?
    
    override var isAsynchronous: Bool {
        return true
    }
    
    init(presentingViewController: UIViewController?)
    {
        self.presentingViewController = presentingViewController
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        let backgroundTaskID = RSTBeginBackgroundTask("com.rileytestut.AltStore.Authenticate")
        
        func finish(_ result: Result<(ALTTeam, ALTCertificate), Swift.Error>)
        {
            print("Finished authenticating with result:", result)
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                do
                {
                    let (altTeam, altCertificate) = try result.get()
                    let altAccount = altTeam.account
                    
                    // Account
                    let account = Account(altAccount, context: context)
                    
                    let otherAccountsFetchRequest = Account.fetchRequest() as NSFetchRequest<Account>
                    otherAccountsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Account.identifier), account.identifier)
                    
                    let otherAccounts = try context.fetch(otherAccountsFetchRequest)
                    otherAccounts.forEach(context.delete(_:))
                    
                    // Team
                    let team = Team(altTeam, account: account, context: context)
                    
                    let otherTeamsFetchRequest = Team.fetchRequest() as NSFetchRequest<Team>
                    otherTeamsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Team.identifier), team.identifier)
                    
                    let otherTeams = try context.fetch(otherTeamsFetchRequest)
                    otherTeams.forEach(context.delete(_:))
                    
                    // Save
                    try context.save()
                    
                    // Update keychain
                    Keychain.shared.appleIDEmailAddress = altAccount.appleID // "account" may have nil appleID since we just saved.
                    Keychain.shared.appleIDPassword = self.appleIDPassword
                    
                    Keychain.shared.signingCertificateIdentifier = altCertificate.identifier
                    Keychain.shared.signingCertificatePrivateKey = altCertificate.privateKey
                    
                    self.resultHandler?(.success((altTeam, altCertificate)))
                }
                catch
                {
                    self.resultHandler?(.failure(error))
                }
                
                self.finish()
                
                DispatchQueue.main.async {
                    self.navigationController.dismiss(animated: true, completion: nil)
                }
                
                RSTEndBackgroundTask(backgroundTaskID)
            }
        }
        
        // Sign In
        self.signIn { (result) in
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success(let account):
                
                // Fetch Team
                self.fetchTeam(for: account) { (result) in
                    switch result
                    {
                    case .failure(let error): finish(.failure(error))
                    case .success(let team):
                        
                        // Fetch Certificate
                        self.fetchCertificate(for: team) { (result) in
                            switch result
                            {
                            case .failure(let error): finish(.failure(error))
                            case .success(let certificate): finish(.success((team, certificate)))
                            }
                        }
                    }
                }
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
                        completionHandler(.failure(Error.cancelled))
                    }
                }
                
                if !self.present(authenticationViewController)
                {
                    completionHandler(.failure(Error.notAuthenticated))
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
                        completionHandler(.failure(Error.cancelled))
                    }
                }
                
                if !self.present(selectTeamViewController)
                {
                    completionHandler(.failure(Error.noTeam))
                }
            }
        }
        
        ALTAppleAPI.shared.fetchTeams(for: account) { (teams, error) in
            switch Result(teams, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let teams):
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    do
                    {
                        let fetchRequest = Team.fetchRequest() as NSFetchRequest<Team>
                        fetchRequest.fetchLimit = 1
                        fetchRequest.returnsObjectsAsFaults = false
                        
                        let fetchedTeams = try context.fetch(fetchRequest)

                        if let fetchedTeam = fetchedTeams.first, let altTeam = teams.first(where: { $0.identifier == fetchedTeam.identifier })
                        {
                            completionHandler(.success(altTeam))
                        }
                        else
                        {
                            selectTeam(from: teams)
                        }
                    }
                    catch
                    {
                        print("Error fetching Teams.", error)
                        
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
                    guard let privateKey = certificate.privateKey else { throw Error.missingPrivateKey }
                    
                    ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
                        do
                        {
                            let certificates = try Result(certificates, error).get()
                            
                            guard let certificate = certificates.first(where: { $0.identifier == certificate.identifier }) else {
                                throw Error.missingCertificate
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
                        completionHandler(.failure(Error.cancelled))
                    }
                }
                
                if !self.present(replaceCertificateViewController)
                {
                    completionHandler(.failure(Error.noCertificate))
                }
            }
        }
        
        ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                if
                    let identifier = Keychain.shared.signingCertificateIdentifier,
                    let privateKey = Keychain.shared.signingCertificatePrivateKey,
                    let certificate = certificates.first(where: { $0.identifier == identifier })
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
