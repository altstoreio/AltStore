//
//  AuthenticationOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas
import Network

import AltKit
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
class AuthenticationOperation: ResultOperation<(ALTSigner, ALTAppleAPISession)>
{
    let group: OperationGroup
    
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
    private var session: ALTAppleAPISession?
    
    private let dispatchQueue = DispatchQueue(label: "com.altstore.AuthenticationOperation")
    
    private var submitCodeAction: UIAlertAction?
    
    init(group: OperationGroup, presentingViewController: UIViewController?)
    {
        self.group = group
        self.presentingViewController = presentingViewController
        
        super.init()
                
        self.progress.totalUnitCount = 3
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.group.error
        {
            self.finish(.failure(error))
            return
        }
                
        // Sign In
        self.signIn() { (result) in
            guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
            
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let account, let session):
                self.session = session
                self.progress.completedUnitCount += 1
                
                // Fetch Team
                self.fetchTeam(for: account, session: session) { (result) in
                    guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
                    
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success(let team):
                        self.progress.completedUnitCount += 1
                        
                        // Fetch Certificate
                        self.fetchCertificate(for: team, session: session) { (result) in
                            guard !self.isCancelled else { return self.finish(.failure(OperationError.cancelled)) }
                            
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success(let certificate):
                                self.progress.completedUnitCount += 1
                                
                                let signer = ALTSigner(team: team, certificate: certificate)
                                self.signer = signer
                                
                                self.showInstructionsIfNecessary() { (didShowInstructions) in
                                    self.finish(.success((signer, session)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    override func finish(_ result: Result<(ALTSigner, ALTAppleAPISession), Error>)
    {
        guard !self.isFinished else { return }
        
        print("Finished authenticating with result:", result)
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.performAndWait {
            do
            {
                let (signer, session) = try result.get()
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
                    super.finish(.success((signer, session)))
                    
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
    func connect(to server: Server, completionHandler: @escaping (Result<NWConnection, Error>) -> Void)
    {
        let connection = NWConnection(to: .service(name: server.service.name, type: server.service.type, domain: server.service.domain, interface: nil), using: .tcp)
        
        connection.stateUpdateHandler = { [unowned connection] (state) in
            switch state
            {
            case .failed(let error):
                print("Failed to connect to service \(server.service.name).", error)
                completionHandler(.failure(ConnectionError.connectionFailed))
                
            case .cancelled:
                completionHandler(.failure(OperationError.cancelled))
                
            case .ready:
                completionHandler(.success(connection))
                
            case .waiting: break
            case .setup: break
            case .preparing: break
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func signIn(completionHandler: @escaping (Result<(ALTAccount, ALTAppleAPISession), Swift.Error>) -> Void)
    {
        func authenticate()
        {
            DispatchQueue.main.async {
                let authenticationViewController = self.storyboard.instantiateViewController(withIdentifier: "authenticationViewController") as! AuthenticationViewController
                authenticationViewController.authenticationHandler = { (appleID, password, completionHandler) in
                    self.authenticate(appleID: appleID, password: password) { (result) in
                        completionHandler(result)
                    }
                }
                authenticationViewController.completionHandler = { (result) in
                    if let (account, session, password) = result
                    {
                        // We presented the Auth UI and the user signed in.
                        // In this case, we'll assume we should show the instructions again.
                        self.shouldShowInstructions = true
                        
                        self.appleIDPassword = password
                        completionHandler(.success((account, session)))
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
            self.authenticate(appleID: appleID, password: password) { (result) in
                switch result
                {
                case .success(let account, let session):
                    self.appleIDPassword = password
                    completionHandler(.success((account, session)))
                    
                case .failure(ALTAppleAPIError.incorrectCredentials), .failure(ALTAppleAPIError.appSpecificPasswordRequired):
                    authenticate()
                    
                case .failure(let error):
                    completionHandler(.failure(error))
                }
            }
        }
        else
        {
            authenticate()
        }
    }
    
    func authenticate(appleID: String, password: String, completionHandler: @escaping (Result<(ALTAccount, ALTAppleAPISession), Swift.Error>) -> Void)
    {
        guard let server = self.group.server else { return completionHandler(.failure(OperationError.invalidParameters)) }
        
        self.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let connection):
                
                let request = AnisetteDataRequest()
                server.send(request, via: connection) { (result) in
                    switch result
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success:
                        
                        server.receiveResponse(from: connection) { (result) in
                            switch result
                            {
                            case .failure(let error):
                                completionHandler(.failure(error))
                                
                            case .success(.error(let response)):
                                completionHandler(.failure(response.error))
                                
                            case .success(.anisetteData(let response)):
                                let verificationHandler: ((@escaping (String?) -> Void) -> Void)?
                                
                                if let presentingViewController = self.presentingViewController
                                {
                                    verificationHandler = { (completionHandler) in
                                        DispatchQueue.main.async {
                                            let alertController = UIAlertController(title: NSLocalizedString("Please enter the 6-digit verification code that was sent to your Apple devices.", comment: ""),
                                                                                    message: nil, preferredStyle: .alert)
                                            alertController.addTextField { (textField) in
                                                textField.autocorrectionType = .no
                                                textField.autocapitalizationType = .none
                                                textField.keyboardType = .numberPad
                                                
                                                NotificationCenter.default.addObserver(self, selector: #selector(AuthenticationOperation.textFieldTextDidChange(_:)), name: UITextField.textDidChangeNotification, object: textField)
                                            }
                                            
                                            let submitAction = UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default) { (action) in
                                                let textField = alertController.textFields?.first
                                                
                                                let code = textField?.text ?? ""
                                                completionHandler(code)
                                            }
                                            submitAction.isEnabled = false
                                            alertController.addAction(submitAction)
                                            self.submitCodeAction = submitAction
                                            
                                            alertController.addAction(UIAlertAction(title: RSTSystemLocalizedString("Cancel"), style: .cancel) { (action) in
                                                completionHandler(nil)
                                            })
                                            
                                            if self.navigationController.presentingViewController != nil
                                            {
                                                self.navigationController.present(alertController, animated: true, completion: nil)
                                            }
                                            else
                                            {
                                                presentingViewController.present(alertController, animated: true, completion: nil)
                                            }
                                        }
                                    }
                                }
                                else
                                {
                                    // No view controller to present security code alert, so don't provide verificationHandler.
                                    verificationHandler = nil
                                }
                                    
                                ALTAppleAPI.shared.authenticate(appleID: appleID, password: password, anisetteData: response.anisetteData,
                                                                verificationHandler: verificationHandler) { (account, session, error) in
                                    if let account = account, let session = session
                                    {
                                        completionHandler(.success((account, session)))
                                    }
                                    else
                                    {
                                        completionHandler(.failure(error ?? OperationError.unknown))
                                    }
                                }
                                
                            case .success:
                                completionHandler(.failure(ALTServerError(.unknownRequest)))
                            }
                        }
                    }
                }
            }
        }
    }
    
    func fetchTeam(for account: ALTAccount, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTTeam, Swift.Error>) -> Void)
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

        ALTAppleAPI.shared.fetchTeams(for: account, session: session) { (teams, error) in
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
    
    func fetchCertificate(for team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTCertificate, Swift.Error>) -> Void)
    {
        func requestCertificate()
        {
            let machineName = "AltStore - " + UIDevice.current.name
            ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session) { (certificate, error) in
                do
                {
                    let certificate = try Result(certificate, error).get()
                    guard let privateKey = certificate.privateKey else { throw AuthenticationError.missingPrivateKey }
                    
                    ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { (certificates, error) in
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
            
            ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { (success, error) in
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
        
        ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { (certificates, error) in
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
        guard let signer = self.signer, let session = self.session else { return completionHandler(false) }
        guard let application = ALTApplication(fileURL: Bundle.main.bundleURL), let provisioningProfile = application.provisioningProfile else { return completionHandler(false) }
        
        // If we're not using the same certificate used to install AltStore, warn user that they need to refresh.
        guard !provisioningProfile.certificates.contains(signer.certificate) else { return completionHandler(false) }
        
        DispatchQueue.main.async {
            let refreshViewController = self.storyboard.instantiateViewController(withIdentifier: "refreshAltStoreViewController") as! RefreshAltStoreViewController
            refreshViewController.signer = signer
            refreshViewController.session = session
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

extension AuthenticationOperation
{
    @objc func textFieldTextDidChange(_ notification: Notification)
    {
        guard let textField = notification.object as? UITextField else { return }
        
        self.submitCodeAction?.isEnabled = (textField.text ?? "").count == 6
    }
}
