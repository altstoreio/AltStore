//
//  ResignAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltSign

@objc(ResignAppOperation)
class ResignAppOperation: ResultOperation<ALTApplication>
{
    let context: AppOperationContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 3
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let app = self.context.app,
            let signer = self.context.group.signer,
            let session = self.context.group.session
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // Prepare Provisioning Profiles
        self.prepareProvisioningProfiles(app.fileURL, team: signer.team, session: session) { (result) in
            guard let profiles = self.process(result) else { return }
            
            // Prepare app bundle
            let prepareAppProgress = Progress.discreteProgress(totalUnitCount: 2)
            self.progress.addChild(prepareAppProgress, withPendingUnitCount: 3)
            
            let prepareAppBundleProgress = self.prepareAppBundle(for: app, profiles: profiles) { (result) in
                guard let appBundleURL = self.process(result) else { return }
                
                print("Resigning App:", self.context.bundleIdentifier)
                
                // Resign app bundle
                let resignProgress = self.resignAppBundle(at: appBundleURL, signer: signer, profiles: Array(profiles.values)) { (result) in
                    guard let resignedURL = self.process(result) else { return }
                    
                    // Finish
                    do
                    {
                        let destinationURL = InstalledApp.refreshedIPAURL(for: app)
                        try FileManager.default.copyItem(at: resignedURL, to: destinationURL, shouldReplace: true)
                        
                        // Use appBundleURL since we need an app bundle, not .ipa.
                        guard let resignedApplication = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                        self.finish(.success(resignedApplication))
                    }
                    catch
                    {
                        self.finish(.failure(error))
                    }
                }
                prepareAppProgress.addChild(resignProgress, withPendingUnitCount: 1)
            }
            prepareAppProgress.addChild(prepareAppBundleProgress, withPendingUnitCount: 1)
        }
    }
    
    func process<T>(_ result: Result<T, Error>) -> T?
    {
        switch result
        {
        case .failure(let error):
            self.finish(.failure(error))
            return nil
            
        case .success(let value):
            guard !self.isCancelled else {
                self.finish(.failure(OperationError.cancelled))
                return nil
            }
            
            return value
        }
    }
}

private extension ResignAppOperation
{
    func prepareProvisioningProfiles(_ fileURL: URL, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<[String: ALTProvisioningProfile], Error>) -> Void)
    {
        guard let app = ALTApplication(fileURL: fileURL) else { return completionHandler(.failure(OperationError.invalidApp)) }
        
        self.prepareProvisioningProfile(for: app, parentApp: nil, team: team, session: session) { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let profile):
                var profiles = [app.bundleIdentifier: profile]
                var error: Error?
                
                let dispatchGroup = DispatchGroup()
                
                for appExtension in app.appExtensions
                {
                    dispatchGroup.enter()
                    
                    self.prepareProvisioningProfile(for: appExtension, parentApp: app, team: team, session: session) { (result) in
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
                        completionHandler(.failure(error))
                    }
                    else
                    {
                        completionHandler(.success(profiles))
                    }
                }
            }
        }
    }
    
    func prepareProvisioningProfile(for app: ALTApplication, parentApp: ALTApplication?, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            
            let preferredBundleID: String
            
            // Check if we have already installed this app with this team before.
            let predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier,
                                        #keyPath(InstalledApp.team.identifier), team.identifier)
            if let installedApp = InstalledApp.first(satisfying: predicate, in: context)
            {
                // This app is already installed, so use the same resigned bundle identifier as before.
                // This way, if we change the identifier format (again), AltStore will continue to use
                // the old bundle identifier to prevent it from installing as a new app.
                preferredBundleID = installedApp.resignedBundleIdentifier
            }
            else
            {
                // This app isn't already installed, so create the resigned bundle identifier ourselves.
                // Or, if the app _is_ installed but with a different team, we need to create a new
                // bundle identifier anyway to prevent collisions with the previous team.
                let parentBundleID = parentApp?.bundleIdentifier ?? app.bundleIdentifier
                let updatedParentBundleID = parentBundleID + "." + team.identifier // Append just team identifier to make it harder to track.
                
                preferredBundleID = app.bundleIdentifier.replacingOccurrences(of: parentBundleID, with: updatedParentBundleID)
            }
            
            let preferredName: String
            
            if let parentApp = parentApp
            {
                preferredName = "\(parentApp.name) - \(app.name)"
            }
            else
            {
                preferredName = app.name
            }
            
            // Register
            self.registerAppID(for: app, name: preferredName, bundleIdentifier: preferredBundleID, team: team, session: session) { (result) in
                switch result
                {
                case .failure(let error): completionHandler(.failure(error))
                case .success(let appID):
                    
                    // Update features
                    self.updateFeatures(for: appID, app: app, team: team, session: session) { (result) in
                        switch result
                        {
                        case .failure(let error): completionHandler(.failure(error))
                        case .success(let appID):
                            
                            // Update app groups
                            self.updateAppGroups(for: appID, app: app, team: team, session: session) { (result) in
                                switch result
                                {
                                case .failure(let error): completionHandler(.failure(error))
                                case .success(let appID):
                                    
                                    // Fetch Provisioning Profile
                                    self.fetchProvisioningProfile(for: appID, team: team, session: session) { (result) in
                                        completionHandler(result)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func registerAppID(for application: ALTApplication, name: String, bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { (appIDs, error) in
            do
            {
                let appIDs = try Result(appIDs, error).get()
                
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleIdentifier })
                {
                    completionHandler(.success(appID))
                }
                else
                {
                    let requiredAppIDs = 1 + application.appExtensions.count
                    let availableAppIDs = max(0, Team.maximumFreeAppIDs - appIDs.count)
                    
                    let sortedExpirationDates = appIDs.compactMap { $0.expirationDate }.sorted(by: { $0 < $1 })
                    
                    if team.type == .free
                    {
                        if requiredAppIDs > availableAppIDs
                        {
                            if let expirationDate = sortedExpirationDates.first
                            {
                                throw OperationError.maximumAppIDLimitReached(application: application, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, nextExpirationDate: expirationDate)
                            }
                            else
                            {
                                throw ALTAppleAPIError(.maximumAppIDLimitReached)
                            }
                        }
                    }
                    
                    ALTAppleAPI.shared.addAppID(withName: name, bundleIdentifier: bundleIdentifier, team: team, session: session) { (appID, error) in
                        do
                        {
                            do
                            {
                                let appID = try Result(appID, error).get()
                                completionHandler(.success(appID))
                            }
                            catch ALTAppleAPIError.maximumAppIDLimitReached
                            {
                                if let expirationDate = sortedExpirationDates.first
                                {
                                    throw OperationError.maximumAppIDLimitReached(application: application, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, nextExpirationDate: expirationDate)
                                }
                                else
                                {
                                    throw ALTAppleAPIError(.maximumAppIDLimitReached)
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
        // TODO: Handle apps belonging to more than one app group.
        guard let applicationGroups = app.entitlements[.appGroups] as? [String], let groupIdentifier = applicationGroups.first else {
            return completionHandler(.success(appID))
        }
        
        func finish(_ result: Result<ALTAppGroup, Error>)
        {
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let group):
                // Assign App Group
                // TODO: Determine whether app already belongs to app group.
                
                ALTAppleAPI.shared.add(appID, to: group, team: team, session: session) { (success, error) in
                    let result = result.map { _ in appID }
                    completionHandler(result)
                }
            }
        }
        
        let adjustedGroupIdentifier = "group.\(team.identifier)." + groupIdentifier
        
        ALTAppleAPI.shared.fetchAppGroups(for: team, session: session) { (groups, error) in
            switch Result(groups, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let groups):
                
                if let group = groups.first(where: { $0.groupIdentifier == adjustedGroupIdentifier })
                {
                    finish(.success(group))
                }
                else
                {
                    // Not all characters are allowed in group names, so we replace periods with spaces (like Apple does).
                    let name = "AltStore " + groupIdentifier.replacingOccurrences(of: ".", with: " ")
                    
                    ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team, session: session) { (group, error) in
                        finish(Result(group, error))
                    }
                }
            }
        }
    }
    
    func fetchProvisioningProfile(for appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team, session: session) { (profile, error) in
            switch Result(profile, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let profile):
                
                // Delete existing profile
                ALTAppleAPI.shared.delete(profile, for: team, session: session) { (success, error) in
                    switch Result(success, error)
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success:
                        
                        // Fetch new provisiong profile
                        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team, session: session) { (profile, error) in
                            completionHandler(Result(profile, error))
                        }
                    }
                }
            }            
        }
    }
    
    func prepareAppBundle(for app: ALTApplication, profiles: [String: ALTProvisioningProfile], completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 1)
        
        let bundleIdentifier = app.bundleIdentifier
        let openURL = InstalledApp.openAppURL(for: app)
        
        let fileURL = app.fileURL
        
        func prepare(_ bundle: Bundle, additionalInfoDictionaryValues: [String: Any] = [:]) throws
        {
            guard let identifier = bundle.bundleIdentifier else { throw ALTError(.missingAppBundle) }
            guard let profile = profiles[identifier] else { throw ALTError(.missingProvisioningProfile) }
            guard var infoDictionary = bundle.infoDictionary else { throw ALTError(.missingInfoPlist) }
            
            infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
            
            for (key, value) in additionalInfoDictionaryValues
            {
                infoDictionary[key] = value
            }
            
            if let appGroups = profile.entitlements[.appGroups] as? [String]
            {
                infoDictionary[Bundle.Info.appGroups] = appGroups
            }
            
            // Add app-specific exported UTI so we can check later if this app (extension) is installed or not.
            let installedAppUTI = ["UTTypeConformsTo": [],
                                   "UTTypeDescription": "AltStore Installed App",
                                   "UTTypeIconFiles": [],
                                   "UTTypeIdentifier": InstalledApp.installedAppUTI(forBundleIdentifier: profile.bundleIdentifier),
                                   "UTTypeTagSpecification": [:]] as [String : Any]
            
            var exportedUTIs = infoDictionary[Bundle.Info.exportedUTIs] as? [[String: Any]] ?? []
            exportedUTIs.append(installedAppUTI)
            infoDictionary[Bundle.Info.exportedUTIs] = exportedUTIs
            
            try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
        }
        
        DispatchQueue.global().async {
            do
            {
                let appBundleURL = self.context.temporaryDirectory.appendingPathComponent("App.app")
                try FileManager.default.copyItem(at: fileURL, to: appBundleURL)
                
                // Become current so we can observe progress from unzipAppBundle().
                progress.becomeCurrent(withPendingUnitCount: 1)
                
                guard let appBundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }
                guard let infoDictionary = appBundle.infoDictionary else { throw ALTError(.missingInfoPlist) }
                
                var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
                
                let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                         "CFBundleURLName": bundleIdentifier,
                                         "CFBundleURLSchemes": [openURL.scheme!]] as [String : Any]
                allURLSchemes.append(altstoreURLScheme)
                
                var additionalValues: [String: Any] = [Bundle.Info.urlTypes: allURLSchemes]

                if self.context.bundleIdentifier == StoreApp.altstoreAppID || self.context.bundleIdentifier == StoreApp.alternativeAltStoreAppID
                {
                    guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
                    additionalValues[Bundle.Info.deviceID] = udid
                    additionalValues[Bundle.Info.serverID] = UserDefaults.standard.preferredServerID
                    
                    if
                        let data = Keychain.shared.signingCertificate,
                        let signingCertificate = ALTCertificate(p12Data: data, password: nil),
                        let encryptingPassword = Keychain.shared.signingCertificatePassword
                    {
                        additionalValues[Bundle.Info.certificateID] = signingCertificate.serialNumber
                        
                        let encryptedData = signingCertificate.encryptedP12Data(withPassword: encryptingPassword)
                        try encryptedData?.write(to: appBundle.certificateURL, options: .atomic)
                    }
                    else
                    {
                        // The embedded certificate + certificate identifier are already in app bundle, no need to update them.
                    }
                }
                
                // Prepare app
                try prepare(appBundle, additionalInfoDictionaryValues: additionalValues)
                
                if let directory = appBundle.builtInPlugInsURL, let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
                {
                    for case let fileURL as URL in enumerator
                    {
                        guard let appExtension = Bundle(url: fileURL) else { throw ALTError(.missingAppBundle) }
                        try prepare(appExtension)
                    }
                }
                
                completionHandler(.success(appBundleURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        return progress
    }
    
    func resignAppBundle(at fileURL: URL, signer: ALTSigner, profiles: [ALTProvisioningProfile], completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let progress = signer.signApp(at: fileURL, provisioningProfiles: profiles) { (success, error) in
            do
            {
                try Result(success, error).get()
                
                let ipaURL = try FileManager.default.zipAppBundle(at: fileURL)
                completionHandler(.success(ipaURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        return progress
    }
}
