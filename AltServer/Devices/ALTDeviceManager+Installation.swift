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

private let appGroupsLock = NSLock()

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
    func installApplication(at url: URL, to device: ALTDevice, appleID: String, password: String, completion: @escaping (Result<ALTApplication, Error>) -> Void)
    {
        let destinationDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        func finish(_ result: Result<ALTApplication, Error>, title: String = "")
        {
            DispatchQueue.main.async {
                completion(result)
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
                                                
                                                if !url.isFileURL
                                                {
                                                    // Show alert before downloading remote .ipa.
                                                    self.showInstallationAlert(appName: NSLocalizedString("AltStore", comment: ""), deviceName: device.name)
                                                }
                                                                                                
                                                self.downloadApp(from: url) { (result) in
                                                    do
                                                    {
                                                        let fileURL = try result.get()
                                                        
                                                        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                                                        
                                                        let appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: destinationDirectoryURL)
                                                        guard let application = ALTApplication(fileURL: appBundleURL) else { throw ALTError(.invalidApp) }
                                                        
                                                        if url.isFileURL
                                                        {
                                                            // Show alert after "downloading" local .ipa.
                                                            self.showInstallationAlert(appName: application.name, deviceName: device.name)
                                                        }
                                                        
                                                        // Refresh anisette data to prevent session timeouts.
                                                        AnisetteDataManager.shared.requestAnisetteData { (result) in
                                                            do
                                                            {
                                                                let anisetteData = try result.get()
                                                                session.anisetteData = anisetteData
                                                                
                                                                self.prepareAllProvisioningProfiles(for: application, device: device, team: team, session: session) { (result) in
                                                                    do
                                                                    {
                                                                        let profiles = try result.get()
                                                                        
                                                                        self.install(application, to: device, team: team, certificate: certificate, profiles: profiles) { (result) in
                                                                            finish(result.map { application }, title: "Failed to Install AltStore")
                                                                        }
                                                                    }
                                                                    catch
                                                                    {
                                                                        finish(.failure(error), title: "Failed to Fetch Provisioning Profiles")
                                                                    }
                                                                }
                                                            }
                                                            catch
                                                            {
                                                                finish(.failure(error), title: "Failed to Refresh Anisette Data")
                                                            }
                                                        }
                                                    }
                                                    catch
                                                    {
                                                        finish(.failure(error), title: "Failed to Download AltStore")
                                                    }
                                                }
                                            }
                                            catch
                                            {
                                                finish(.failure(error), title: "Failed to Fetch Certificate")
                                            }
                                        }
                                    }
                                    catch
                                    {
                                        finish(.failure(error), title: "Failed to Register Device")
                                    }
                                }
                            }
                            catch
                            {
                                finish(.failure(error), title: "Failed to Fetch Team")
                            }
                        }
                    }
                    catch
                    {
                        finish(.failure(error), title: "Failed to Authenticate")
                    }
                }
            }
            catch
            {
                finish(.failure(error), title: "Failed to Fetch Anisette Data")
            }
        }
    }
}

private extension ALTDeviceManager
{
    func downloadApp(from url: URL, completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        guard !url.isFileURL else { return completionHandler(.success(url)) }
        
        let downloadTask = URLSession.shared.downloadTask(with: url) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                completionHandler(.success(fileURL))
                
                do { try FileManager.default.removeItem(at: fileURL) }
                catch { print("Failed to remove downloaded .ipa.", error) }
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
        ALTAppleAPI.shared.fetchTeams(for: account, session: session) { (teams, error) in
            do
            {
                let teams = try Result(teams, error).get()
                
                if let team = teams.first(where: { $0.type == .individual })
                {
                    return completionHandler(.success(team))
                }
                else if let team = teams.first(where: { $0.type == .free })
                {
                    return completionHandler(.success(team))
                }
                else if let team = teams.first
                {
                    return completionHandler(.success(team))
                }
                else
                {
                    throw InstallError.noTeam
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func fetchCertificate(for team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTCertificate, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                let applicationSupportDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let altserverDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("com.rileytestut.AltServer")
                let certificatesDirectoryURL = altserverDirectoryURL.appendingPathComponent("Certificates")
                
                try FileManager.default.createDirectory(at: certificatesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                
                let certificateFileURL = certificatesDirectoryURL.appendingPathComponent(team.identifier + ".p12")
                
                var isCancelled = false
                
                // Check if there is another AltStore certificate, which means AltStore has been installed with this Apple ID before.
                if let previousCertificate = certificates.first(where: { $0.machineName?.starts(with: "AltStore") == true })
                {
                    if FileManager.default.fileExists(atPath: certificateFileURL.path),
                       let data = try? Data(contentsOf: certificateFileURL),
                       let certificate = ALTCertificate(p12Data: data, password: previousCertificate.machineIdentifier)
                    {
                        // Manually set machineIdentifier so we can encrypt + embed certificate if needed.
                        certificate.machineIdentifier = previousCertificate.machineIdentifier
                        return completionHandler(.success(certificate))
                    }
                                        
                    DispatchQueue.main.sync {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Multiple AltServers Not Supported", comment: "")
                        alert.informativeText = NSLocalizedString("Please use the same AltServer you previously used with this Apple ID, or else apps installed with other AltServers will stop working.\n\nAre you sure you want to continue?", comment: "")
                        
                        alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                        
                        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                        
                        let buttonIndex = alert.runModal()
                        if buttonIndex == NSApplication.ModalResponse.alertSecondButtonReturn
                        {
                            isCancelled = true
                        }
                    }
                    
                    guard !isCancelled else { return completionHandler(.failure(InstallError.cancelled)) }
                }
                
                if team.type != .free
                {
                    DispatchQueue.main.sync {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Installing this app will revoke your iOS development certificate.", comment: "")
                        alert.informativeText = NSLocalizedString("""
This will not affect apps you've submitted to the App Store, but may cause apps you've installed to your devices with Xcode to stop working until you reinstall them.

To prevent this from happening, feel free to try again with another Apple ID.
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
                    
                    guard !isCancelled else { return completionHandler(.failure(InstallError.cancelled)) }
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
                                    
                                    if let machineIdentifier = certificate.machineIdentifier,
                                       let encryptedData = certificate.encryptedP12Data(withPassword: machineIdentifier)
                                    {
                                        // Cache certificate.
                                        do { try encryptedData.write(to: certificateFileURL, options: .atomic) }
                                        catch { print("Failed to cache certificate:", error) }
                                    }
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
    
    func prepareAllProvisioningProfiles(for application: ALTApplication, device: ALTDevice, team: ALTTeam, session: ALTAppleAPISession,
                                        completion: @escaping (Result<[String: ALTProvisioningProfile], Error>) -> Void)
    {
        self.prepareProvisioningProfile(for: application, parentApp: nil, device: device, team: team, session: session) { (result) in
            do
            {
                let profile = try result.get()
                
                var profiles = [application.bundleIdentifier: profile]
                var error: Error?
                
                let dispatchGroup = DispatchGroup()
                
                for appExtension in application.appExtensions
                {
                    dispatchGroup.enter()
                    
                    self.prepareProvisioningProfile(for: appExtension, parentApp: application, device: device, team: team, session: session) { (result) in
                        switch result
                        {
                        case .failure(let e): error = e
                        case .success(let profile): profiles[appExtension.bundleIdentifier] = profile
                        }
                        
                        dispatchGroup.leave()
                    }
                }
                
                dispatchGroup.notify(queue: .global()) {
                    if let error = error
                    {
                        completion(.failure(error))
                    }
                    else
                    {
                        completion(.success(profiles))
                    }
                }
            }
            catch
            {
                completion(.failure(error))
            }
        }
    }
    
    func prepareProvisioningProfile(for application: ALTApplication, parentApp: ALTApplication?, device: ALTDevice, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        let parentBundleID = parentApp?.bundleIdentifier ?? application.bundleIdentifier
        let updatedParentBundleID: String
        
        if application.isAltStoreApp
        {
            // Use legacy bundle ID format for AltStore (and its extensions).
            updatedParentBundleID = "com.\(team.identifier).\(parentBundleID)"
        }
        else
        {
            updatedParentBundleID = parentBundleID + "." + team.identifier // Append just team identifier to make it harder to track.
        }
        
        let bundleID = application.bundleIdentifier.replacingOccurrences(of: parentBundleID, with: updatedParentBundleID)
        
        let preferredName: String
        
        if let parentApp = parentApp
        {
            preferredName = parentApp.name + " " + application.name
        }
        else
        {
            preferredName = application.name
        }
        
        self.registerAppID(name: preferredName, bundleID: bundleID, team: team, session: session) { (result) in
            do
            {
                let appID = try result.get()
                
                self.updateFeatures(for: appID, app: application, team: team, session: session) { (result) in
                    do
                    {
                        let appID = try result.get()
                        
                        self.updateAppGroups(for: appID, app: application, team: team, session: session) { (result) in
                            do
                            {
                                let appID = try result.get()
                                
                                self.fetchProvisioningProfile(for: appID, device: device, team: team, session: session) { (result) in
                                    completionHandler(result)
                                }
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
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func registerAppID(name appName: String, bundleID: String, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
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
        
        var updateFeatures = false
        
        // Determine whether the required features are already enabled for the AppID.
        for (feature, value) in features
        {
            if let appIDValue = appID.features[feature] as AnyObject?, (value as AnyObject).isEqual(appIDValue)
            {
                // AppID already has this feature enabled and the values are the same.
                continue
            }
            else
            {
                // AppID either doesn't have this feature enabled or the value has changed,
                // so we need to update it to reflect new values.
                updateFeatures = true
                break
            }
        }
        
        if updateFeatures
        {
            let appID = appID.copy() as! ALTAppID
            appID.features = features
            
            ALTAppleAPI.shared.update(appID, team: team, session: session) { (appID, error) in
                completionHandler(Result(appID, error))
            }
        }
        else
        {
            completionHandler(.success(appID))
        }
    }
    
    func updateAppGroups(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let applicationGroups = app.entitlements[.appGroups] as? [String] ?? []
        if applicationGroups.isEmpty
        {
            guard let isAppGroupsEnabled = appID.features[.appGroups] as? Bool, isAppGroupsEnabled else {
                // No app groups, and we also haven't enabled the feature, so don't continue.
                // For apps with no app groups but have had the feature enabled already
                // we'll continue and assign the app ID to an empty array
                // in case we need to explicitly remove them.
                return completionHandler(.success(appID))
            }
        }
        
        // Dispatch onto global queue to prevent appGroupsLock deadlock.
        DispatchQueue.global().async {
            
            // Ensure we're not concurrently fetching and updating app groups,
            // which can lead to race conditions such as adding an app group twice.
            appGroupsLock.lock()
            
            func finish(_ result: Result<ALTAppID, Error>)
            {
                appGroupsLock.unlock()
                completionHandler(result)
            }
            
            ALTAppleAPI.shared.fetchAppGroups(for: team, session: session) { (groups, error) in
                switch Result(groups, error)
                {
                case .failure(let error): finish(.failure(error))
                case .success(let fetchedGroups):
                    let dispatchGroup = DispatchGroup()
                    
                    var groups = [ALTAppGroup]()
                    var errors = [Error]()
                    
                    for groupIdentifier in applicationGroups
                    {
                        let adjustedGroupIdentifier = groupIdentifier + "." + team.identifier
                        
                        if let group = fetchedGroups.first(where: { $0.groupIdentifier == adjustedGroupIdentifier })
                        {
                            groups.append(group)
                        }
                        else
                        {
                            dispatchGroup.enter()
                            
                            // Not all characters are allowed in group names, so we replace periods with spaces (like Apple does).
                            let name = "AltStore " + groupIdentifier.replacingOccurrences(of: ".", with: " ")
                            
                            ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team, session: session) { (group, error) in
                                switch Result(group, error)
                                {
                                case .success(let group): groups.append(group)
                                case .failure(let error): errors.append(error)
                                }
                                
                                dispatchGroup.leave()
                            }
                        }
                    }
                    
                    dispatchGroup.notify(queue: .global()) {
                        if let error = errors.first
                        {
                            finish(.failure(error))
                        }
                        else
                        {
                            ALTAppleAPI.shared.assign(appID, to: Array(groups), team: team, session: session) { (success, error) in
                                let result = Result(success, error)
                                finish(result.map { _ in appID })
                            }
                        }
                    }
                }
            }
        }
    }
    
    func register(_ device: ALTDevice, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchDevices(for: team, types: device.type, session: session) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == device.identifier })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: device.name, identifier: device.identifier, type: device.type, team: team, session: session) { (device, error) in
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
    
    func fetchProvisioningProfile(for appID: ALTAppID, device: ALTDevice, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: device.type, team: team, session: session) { (profile, error) in
            completionHandler(Result(profile, error))
        }
    }
    
    func install(_ application: ALTApplication, to device: ALTDevice, team: ALTTeam, certificate: ALTCertificate, profiles: [String: ALTProvisioningProfile], completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        func prepare(_ bundle: Bundle, additionalInfoDictionaryValues: [String: Any] = [:]) throws
        {
            guard let identifier = bundle.bundleIdentifier else { throw ALTError(.missingAppBundle) }
            guard let profile = profiles[identifier] else { throw ALTError(.missingProvisioningProfile) }
            guard var infoDictionary = bundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }
            
            infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
            infoDictionary[Bundle.Info.altBundleID] = identifier

            for (key, value) in additionalInfoDictionaryValues
            {
                infoDictionary[key] = value
            }
            
            if let appGroups = profile.entitlements[.appGroups] as? [String]
            {
                infoDictionary[Bundle.Info.appGroups] = appGroups
            }
            
            try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
        }
        
        DispatchQueue.global().async {
            do
            {
                guard let appBundle = Bundle(url: application.fileURL) else { throw ALTError(.missingAppBundle) }
                guard let infoDictionary = appBundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }
                
                let openAppURL = URL(string: "altstore-" + application.bundleIdentifier + "://")!
                
                var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
                
                // Embed open URL so AltBackup can return to AltStore.
                let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                         "CFBundleURLName": application.bundleIdentifier,
                                         "CFBundleURLSchemes": [openAppURL.scheme!]] as [String : Any]
                allURLSchemes.append(altstoreURLScheme)
                
                var additionalValues: [String: Any] = [Bundle.Info.urlTypes: allURLSchemes]
                
                if application.isAltStoreApp
                {
                    additionalValues[Bundle.Info.deviceID] = device.identifier
                    additionalValues[Bundle.Info.serverID] = UserDefaults.standard.serverID
                    
                    if
                        let machineIdentifier = certificate.machineIdentifier,
                        let encryptedData = certificate.encryptedP12Data(withPassword: machineIdentifier)
                    {
                        additionalValues[Bundle.Info.certificateID] = certificate.serialNumber
                        
                        let certificateURL = application.fileURL.appendingPathComponent("ALTCertificate.p12")
                        try encryptedData.write(to: certificateURL, options: .atomic)
                    }
                }
                
                try prepare(appBundle, additionalInfoDictionaryValues: additionalValues)
                
                for appExtension in application.appExtensions
                {
                    guard let bundle = Bundle(url: appExtension.fileURL) else { throw ALTError(.missingAppBundle) }
                    try prepare(bundle)
                }
                
                let resigner = ALTSigner(team: team, certificate: certificate)
                resigner.signApp(at: application.fileURL, provisioningProfiles: Array(profiles.values)) { (success, error) in
                    do
                    {
                        try Result(success, error).get()
                        
                        let activeProfiles: Set<String>? = (team.type == .free && application.isAltStoreApp) ? Set(profiles.values.map(\.bundleIdentifier)) : nil
                        ALTDeviceManager.shared.installApp(at: application.fileURL, toDeviceWithUDID: device.identifier, activeProvisioningProfiles: activeProfiles) { (success, error) in
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
    
    func showInstallationAlert(appName: String, deviceName: String)
    {
        let content = UNMutableNotificationContent()
        content.title = String(format: NSLocalizedString("Installing %@ to %@...", comment: ""), appName, deviceName)
        content.body = NSLocalizedString("This may take a few seconds.", comment: "")
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
