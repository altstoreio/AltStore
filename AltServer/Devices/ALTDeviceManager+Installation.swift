//
//  ALTDeviceManager+Installation.swift
//  AltServer
//
//  Created by Riley Testut on 7/1/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa
import UserNotifications
import ObjectiveC

#if STAGING
private let appURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore.ipa")!
#else
private let appURL = URL(string: "https://f000.backblazeb2.com/file/altstore/altstore.ipa")!
#endif

enum InstallError: LocalizedError
{
    case cancelled
    case noTeam
    case missingPrivateKey
    case missingCertificate
    
    var errorDescription: String? {
        switch self
        {
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .noTeam: return "You are not a member of any developer teams."
        case .missingPrivateKey: return "The developer certificate's private key could not be found."
        case .missingCertificate: return "The developer certificate could not be found."
        }
    }
}

extension ALTDeviceManager
{
    func installAltStore(to device: ALTDevice, appleID: String, password: String, completion: @escaping (Result<Void, Error>) -> Void)
    {
        let destinationDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        func finish(_ error: Error?, title: String = "")
        {
            DispatchQueue.main.async {
                if let error = error
                {
                    completion(.failure(error))
                }
                else
                {
                    completion(.success(()))
                }
            }
            
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
        }
        
        AnisetteDataManager.shared.requestAnisetteData { (result) in
            do
            {
                let anisetteData = try result.get()
                
                self.authenticate(appleID: appleID, password: password, anisetteData: anisetteData) { (result) in
                    do
                    {
                        let (account, session) = try result.get()
                        
                        self.fetchTeam(for: account, session: session) { (result) in
                            do
                            {
                                let team = try result.get()
                                
                                self.register(device, team: team, session: session) { (result) in
                                    do
                                    {
                                        let device = try result.get()
                                        
                                        self.fetchCertificate(for: team, session: session) { (result) in
                                            do
                                            {
                                                let certificate = try result.get()
                                                
                                                let content = UNMutableNotificationContent()
                                                content.title = String(format: NSLocalizedString("Installing AltStore to %@...", comment: ""), device.name)
                                                content.body = NSLocalizedString("This may take a few seconds.", comment: "")
                                                
                                                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                                                UNUserNotificationCenter.current().add(request)
                                                
                                                self.downloadApp { (result) in
                                                    do
                                                    {
                                                        let fileURL = try result.get()
                                                        
                                                        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                                                        
                                                        let appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: destinationDirectoryURL)
                                                        
                                                        do
                                                        {
                                                            try FileManager.default.removeItem(at: fileURL)
                                                        }
                                                        catch
                                                        {
                                                            print("Failed to remove downloaded .ipa.", error)
                                                        }
                                                        
                                                        guard let application = ALTApplication(fileURL: appBundleURL) else { throw ALTError(.invalidApp) }
                                                        
                                                        // Refresh anisette data to prevent session timeouts.
                                                        AnisetteDataManager.shared.requestAnisetteData { (result) in
                                                            do
                                                            {
                                                                let anisetteData = try result.get()
                                                                session.anisetteData = anisetteData
                                                                
                                                                self.registerAppID(name: "AltStore", identifier: "com.rileytestut.AltStore", team: team, session: session) { (result) in
                                                                    do
                                                                    {
                                                                        let appID = try result.get()
                                                                        
                                                                        self.updateFeatures(for: appID, app: application, team: team, session: session) { (result) in
                                                                            do
                                                                            {
                                                                                let appID = try result.get()
                                                                                
                                                                                self.fetchProvisioningProfile(for: appID, team: team, session: session) { (result) in
                                                                                    do
                                                                                    {
                                                                                        let provisioningProfile = try result.get()
                                                                                        
                                                                                        self.install(application, to: device, team: team, appID: appID, certificate: certificate, profile: provisioningProfile) { (result) in
                                                                                            finish(result.error, title: "Failed to Install AltStore")
                                                                                        }
                                                                                    }
                                                                                    catch
                                                                                    {
                                                                                        finish(error, title: "Failed to Fetch Provisioning Profile")
                                                                                    }
                                                                                }
                                                                            }
                                                                            catch
                                                                            {
                                                                                finish(error, title: "Failed to Update App ID")
                                                                            }
                                                                        }
                                                                    }
                                                                    catch
                                                                    {
                                                                        finish(error, title: "Failed to Register App")
                                                                    }
                                                                }
                                                            }
                                                            catch
                                                            {
                                                                finish(error, title: "Failed to Refresh Anisette Data")
                                                            }
                                                        }
                                                    }
                                                    catch
                                                    {
                                                        finish(error, title: "Failed to Download AltStore")
                                                    }
                                                }
                                            }
                                            catch
                                            {
                                                finish(error, title: "Failed to Fetch Certificate")
                                            }
                                        }
                                    }
                                    catch
                                    {
                                        finish(error, title: "Failed to Register Device")
                                    }
                                }
                            }
                            catch
                            {
                                finish(error, title: "Failed to Fetch Team")
                            }
                        }
                    }
                    catch
                    {
                        finish(error, title: "Failed to Authenticate")
                    }
                }
            }
            catch
            {
                finish(error, title: "Failed to Fetch Anisette Data")
            }
        }
    }
    
    func downloadApp(completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        let downloadTask = URLSession.shared.downloadTask(with: appURL) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                completionHandler(.success(fileURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        downloadTask.resume()
    }
    
    func authenticate(appleID: String, password: String, anisetteData: ALTAnisetteData, completionHandler: @escaping (Result<(ALTAccount, ALTAppleAPISession), Error>) -> Void)
    {
        func handleVerificationCode(_ completionHandler: @escaping (String?) -> Void)
        {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Two-Factor Authentication Enabled", comment: "")
                alert.informativeText = NSLocalizedString("Please enter the 6-digit verification code that was sent to your Apple devices.", comment: "")
                
                let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
                textField.delegate = self
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.placeholderString = NSLocalizedString("123456", comment: "")
                alert.accessoryView = textField
                alert.window.initialFirstResponder = textField
                
                alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                
                self.securityCodeAlert = alert
                self.securityCodeTextField = textField
                self.validate()
                
                NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn
                {
                    let code = textField.stringValue
                    completionHandler(code)
                }
                else
                {
                    completionHandler(nil)
                }
            }
        }
        
        ALTAppleAPI.shared.authenticate(appleID: appleID, password: password, anisetteData: anisetteData, verificationHandler: handleVerificationCode) { (account, session, error) in
            if let account = account, let session = session
            {
                completionHandler(.success((account, session)))
            }
            else
            {
                completionHandler(.failure(error ?? ALTAppleAPIError(.unknown)))
            }
        }
    }
    
    func fetchTeam(for account: ALTAccount, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTTeam, Error>) -> Void)
    {
        func finish(_ result: Result<ALTTeam, Error>)
        {
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success(let team):
                
                var isCancelled = false
                
                if team.type != .free
                {
                    DispatchQueue.main.sync {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Installing AltStore will revoke your iOS development certificate.", comment: "")
                        alert.informativeText = NSLocalizedString("""
This will not affect apps you've submitted to the App Store, but may cause apps you've installed to your devices with Xcode to stop working until you reinstall them.

To prevent this from happening, feel free to try again with another Apple ID to install AltStore.
""", comment: "")
                        
                        alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                        
                        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                        
                        let buttonIndex = alert.runModal()
                        if buttonIndex == NSApplication.ModalResponse.alertSecondButtonReturn
                        {
                            isCancelled = true
                        }
                    }
                    
                    if isCancelled
                    {
                        return completionHandler(.failure(InstallError.cancelled))
                    }
                }
                
                completionHandler(.success(team))
            }
        }
        
        ALTAppleAPI.shared.fetchTeams(for: account, session: session) { (teams, error) in
            do
            {
                let teams = try Result(teams, error).get()
                
                if let team = teams.first(where: { $0.type == .free })
                {
                    return finish(.success(team))
                }
                else if let team = teams.first(where: { $0.type == .individual })
                {
                    return finish(.success(team))
                }
                else if let team = teams.first
                {
                    return finish(.success(team))
                }
                else
                {
                    throw InstallError.noTeam
                }
            }
            catch
            {
                finish(.failure(error))
            }
        }
    }
    
    func fetchCertificate(for team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTCertificate, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                // Check if there is another AltStore certificate, which means AltStore has been installed with this Apple ID before.
                if certificates.contains(where: { $0.machineName?.starts(with: "AltStore") == true })
                {
                    var isCancelled = false
                    
                    DispatchQueue.main.sync {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("AltStore already installed on another device.", comment: "")
                        alert.informativeText = NSLocalizedString("Apps installed with AltStore on your other devices will stop working. Are you sure you want to continue?", comment: "")
                        
                        alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                        
                        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                        
                        let buttonIndex = alert.runModal()
                        if buttonIndex == NSApplication.ModalResponse.alertSecondButtonReturn
                        {
                            isCancelled = true
                        }
                    }
                    
                    if isCancelled
                    {
                        return completionHandler(.failure(InstallError.cancelled))
                    }
                }
                
                if let certificate = certificates.first
                {
                    ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { (success, error) in
                        do
                        {
                            try Result(success, error).get()
                            self.fetchCertificate(for: team, session: session, completionHandler: completionHandler)
                        }
                        catch
                        {
                            completionHandler(.failure(error))
                        }
                    }
                }
                else
                {
                    ALTAppleAPI.shared.addCertificate(machineName: "AltStore", to: team, session: session) { (certificate, error) in
                        do
                        {
                            let certificate = try Result(certificate, error).get()
                            guard let privateKey = certificate.privateKey else { throw InstallError.missingPrivateKey }
                            
                            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { (certificates, error) in
                                do
                                {
                                    let certificates = try Result(certificates, error).get()
                                    
                                    guard let certificate = certificates.first(where: { $0.serialNumber == certificate.serialNumber }) else {
                                        throw InstallError.missingCertificate
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
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func registerAppID(name appName: String, identifier: String, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let bundleID = "com.\(team.identifier).\(identifier)"
        
        ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { (appIDs, error) in
            do
            {
                let appIDs = try Result(appIDs, error).get()
                
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleID })
                {
                    completionHandler(.success(appID))
                }
                else
                {
                    ALTAppleAPI.shared.addAppID(withName: appName, bundleIdentifier: bundleID, team: team, session: session) { (appID, error) in
                        completionHandler(Result(appID, error))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func updateFeatures(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let requiredFeatures = app.entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement: entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = app.entitlements[.appGroups] as? [String], !applicationGroups.isEmpty
        {
            features[.appGroups] = true
        }
        
        let appID = appID.copy() as! ALTAppID
        appID.features = features
        
        ALTAppleAPI.shared.update(appID, team: team, session: session) { (appID, error) in
            completionHandler(Result(appID, error))
        }
    }
    
    func register(_ device: ALTDevice, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchDevices(for: team, session: session) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == device.identifier })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: device.name, identifier: device.identifier, team: team, session: session) { (device, error) in
                        completionHandler(Result(device, error))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func fetchProvisioningProfile(for appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team, session: session) { (profile, error) in
            completionHandler(Result(profile, error))
        }
    }
    
    func install(_ application: ALTApplication, to device: ALTDevice, team: ALTTeam, appID: ALTAppID, certificate: ALTCertificate, profile: ALTProvisioningProfile, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        DispatchQueue.global().async {
            do
            {
                let infoPlistURL = application.fileURL.appendingPathComponent("Info.plist")
                
                guard var infoDictionary = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] else { throw ALTError(.missingInfoPlist) }
                infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
                infoDictionary[Bundle.Info.deviceID] = device.identifier
                infoDictionary[Bundle.Info.serverID] = UserDefaults.standard.serverID
                infoDictionary[Bundle.Info.certificateID] = certificate.serialNumber
                try (infoDictionary as NSDictionary).write(to: infoPlistURL)
                                
                if
                    let machineIdentifier = certificate.machineIdentifier,
                    let encryptedData = certificate.encryptedP12Data(withPassword: machineIdentifier)
                {
                    let certificateURL = application.fileURL.appendingPathComponent("ALTCertificate.p12")
                    try encryptedData.write(to: certificateURL, options: .atomic)
                }
                
                let resigner = ALTSigner(team: team, certificate: certificate)
                resigner.signApp(at: application.fileURL, provisioningProfiles: [profile]) { (success, error) in
                    do
                    {
                        try Result(success, error).get()
                        
                        ALTDeviceManager.shared.installApp(at: application.fileURL, toDeviceWithUDID: device.identifier) { (success, error) in
                            completionHandler(Result(success, error))
                        }
                    }
                    catch
                    {
                        print("Failed to install app", error)
                        completionHandler(.failure(error))
                    }
                }
            }
            catch
            {
                print("Failed to install AltStore", error)
                completionHandler(.failure(error))
            }
        }
    }
}

private var securityCodeAlertKey = 0
private var securityCodeTextFieldKey = 0

extension ALTDeviceManager: NSTextFieldDelegate
{
    var securityCodeAlert: NSAlert? {
        get { return objc_getAssociatedObject(self, &securityCodeAlertKey) as? NSAlert }
        set { objc_setAssociatedObject(self, &securityCodeAlertKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var securityCodeTextField: NSTextField? {
        get { return objc_getAssociatedObject(self, &securityCodeTextFieldKey) as? NSTextField }
        set { objc_setAssociatedObject(self, &securityCodeTextFieldKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    public func controlTextDidChange(_ obj: Notification)
    {
        self.validate()
    }
    
    public func controlTextDidEndEditing(_ obj: Notification)
    {
        self.validate()
    }
    
    private func validate()
    {
        guard let code = self.securityCodeTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        
        if code.count == 6
        {
            self.securityCodeAlert?.buttons.first?.isEnabled = true
        }
        else
        {
            self.securityCodeAlert?.buttons.first?.isEnabled = false
        }
        
        self.securityCodeAlert?.layout()
    }
}
