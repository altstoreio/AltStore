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
    
    private lazy var navigationController: UINavigationController = {
        let navigationController = self.storyboard.instantiateViewController(withIdentifier: "navigationController") as! UINavigationController
        if #available(iOS 13.0, *)
        {
            navigationController.isModalInPresentation = true
        }
        return navigationController
    }()
    
    private lazy var storyboard = UIStoryboard(name: "Authentication", bundle: nil)
    
    private var appleIDPassword: String?
    private var shouldShowInstructions = false
    
    private var signer: ALTSigner?
    
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
                                self.signer = signer
                                
                                self.showInstructionsIfNecessary() { (didShowInstructions) in
                                    self.finish(.success(signer))
                                }                                
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
                
                Keychain.shared.signingCertificate = signer.certificate.p12Data()
                Keychain.shared.signingCertificatePassword = signer.certificate.machineIdentifier
                
                // Refresh screen must go last since a successful refresh will cause the app to quit.
                self.showRefreshScreenIfNecessary() { (didShowRefreshAlert) in
                    super.finish(.success(signer))
                    
                    DispatchQueue.main.async {
                        self.navigationController.dismiss(animated: true, completion: nil)
                    }
                }
            }
            catch
            {
                super.finish(.failure(error))
                
                DispatchQueue.main.async {
                    self.navigationController.dismiss(animated: true, completion: nil)
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
        
        self.navigationController.view.tintColor = .white
        
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
                        // We presented the Auth UI and the user signed in.
                        // In this case, we'll assume we should show the instructions again.
                        self.shouldShowInstructions = true
                        
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
            if let team = teams.first(where: { $0.type == .free })
            {
                return completionHandler(.success(team))
            }
            else if let team = teams.first(where: { $0.type == .individual })
            {
                return completionHandler(.success(team))
            }
            else if let team = teams.first
            {
                return completionHandler(.success(team))
            }
            else
            {
                return completionHandler(.failure(AuthenticationError.noTeam))
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
            guard let certificate = certificates.first else { return completionHandler(.failure(AuthenticationError.noCertificate)) }
            
            ALTAppleAPI.shared.revoke(certificate, for: team) { (success, error) in
                if let error = error, !success
                {
                    completionHandler(.failure(error))
                }
                else
                {
                    requestCertificate()
                }
            }
        }
        
        ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                if
                    let data = Keychain.shared.signingCertificate,
                    let localCertificate = ALTCertificate(p12Data: data, password: nil),
                    let certificate = certificates.first(where: { $0.serialNumber == localCertificate.serialNumber })
                {
                    // We have a certificate stored in the keychain and it hasn't been revoked.
                    localCertificate.machineIdentifier = certificate.machineIdentifier
                    completionHandler(.success(localCertificate))
                }
                else if
                    let serialNumber = Keychain.shared.signingCertificateSerialNumber,
                    let privateKey = Keychain.shared.signingCertificatePrivateKey,
                    let certificate = certificates.first(where: { $0.serialNumber == serialNumber })
                {
                    // LEGACY
                    // We have the private key for one of the certificates, so add it to certificate and use it.
                    certificate.privateKey = privateKey
                    completionHandler(.success(certificate))
                }
                else if
                    let serialNumber = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.certificateID) as? String,
                    let certificate = certificates.first(where: { $0.serialNumber == serialNumber }),
                    let machineIdentifier = certificate.machineIdentifier,
                    FileManager.default.fileExists(atPath: Bundle.main.certificateURL.path),
                    let data = try? Data(contentsOf: Bundle.main.certificateURL),
                    let localCertificate = ALTCertificate(p12Data: data, password: machineIdentifier)
                {
                    // We have an embedded certificate that hasn't been revoked.
                    localCertificate.machineIdentifier = machineIdentifier
                    completionHandler(.success(localCertificate))
                }
                else if certificates.isEmpty
                {
                    // No certificates, so request a new one.
                    requestCertificate()
                }
                else
                {
                    // We don't have private keys for any of the certificates,
                    // so we need to revoke one and create a new one.
                    replaceCertificate(from: certificates)
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func showInstructionsIfNecessary(completionHandler: @escaping (Bool) -> Void)
    {
        guard self.shouldShowInstructions else { return completionHandler(false) }
        
        DispatchQueue.main.async {
            let instructionsViewController = self.storyboard.instantiateViewController(withIdentifier: "instructionsViewController") as! InstructionsViewController
            instructionsViewController.showsBottomButton = true
            instructionsViewController.completionHandler = {
                completionHandler(true)
            }
            
            if !self.present(instructionsViewController)
            {
                completionHandler(false)
            }
        }
    }
    
    func showRefreshScreenIfNecessary(completionHandler: @escaping (Bool) -> Void)
    {
        guard let signer = self.signer else { return completionHandler(false) }
        guard let application = ALTApplication(fileURL: Bundle.main.bundleURL), let provisioningProfile = application.provisioningProfile else { return completionHandler(false) }
        
        // If we're not using the same certificate used to install AltStore, warn user that they need to refresh.
        guard !provisioningProfile.certificates.contains(signer.certificate) else { return completionHandler(false) }
        
        DispatchQueue.main.async {
            let refreshViewController = self.storyboard.instantiateViewController(withIdentifier: "refreshAltStoreViewController") as! RefreshAltStoreViewController
            refreshViewController.signer = signer
            refreshViewController.completionHandler = { _ in
                completionHandler(true)
            }
            
            if !self.present(refreshViewController)
            {
                completionHandler(false)
            }
        }
    }
}
