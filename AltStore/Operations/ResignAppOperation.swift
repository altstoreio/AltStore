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
            let signer = self.context.group.signer
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // Register Device
        self.registerCurrentDevice(for: signer.team) { (result) in
            guard let _ = self.process(result) else { return }
            
            // Prepare Provisioning Profiles
            self.prepareProvisioningProfiles(app.fileURL, team: signer.team) { (result) in
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
    func registerCurrentDevice(for team: ALTTeam, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else {
            return completionHandler(.failure(OperationError.unknownUDID))
        }
        
        ALTAppleAPI.shared.fetchDevices(for: team) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == udid })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: UIDevice.current.name, identifier: udid, team: team) { (device, error) in
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
    
    func prepareProvisioningProfiles(_ fileURL: URL, team: ALTTeam, completionHandler: @escaping (Result<[String: ALTProvisioningProfile], Error>) -> Void)
    {
        guard let bundle = Bundle(url: fileURL), let app = ALTApplication(fileURL: fileURL) else { return completionHandler(.failure(OperationError.invalidApp)) }
        
        let dispatchGroup = DispatchGroup()
        
        var profiles = [String: ALTProvisioningProfile]()
        var error: Error?
        
        dispatchGroup.enter()
        
        self.prepareProvisioningProfile(for: app, team: team) { (result) in
            switch result
            {
            case .failure(let e): error = e
            case .success(let profile):
                profiles[app.bundleIdentifier] = profile
            }
            dispatchGroup.leave()
        }
        
        if let directory = bundle.builtInPlugInsURL, let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
        {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "appex"
            {
                guard let appExtension = ALTApplication(fileURL: fileURL) else { continue }
                
                dispatchGroup.enter()
                
                self.prepareProvisioningProfile(for: appExtension, team: team) { (result) in
                    switch result
                    {
                    case .failure(let e): error = e
                    case .success(let profile):
                        profiles[appExtension.bundleIdentifier] = profile
                    }
                    dispatchGroup.leave()
                }
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
    
    func prepareProvisioningProfile(for app: ALTApplication, team: ALTTeam, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        // Register
        self.register(app, team: team) { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let appID):
                
                // Update features
                self.updateFeatures(for: appID, app: app, team: team) { (result) in
                    switch result
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success(let appID):
                        
                        // Update app groups
                        self.updateAppGroups(for: appID, app: app, team: team) { (result) in
                            switch result
                            {
                            case .failure(let error): completionHandler(.failure(error))
                            case .success(let appID):
                                
                                // Fetch Provisioning Profile
                                self.fetchProvisioningProfile(for: appID, team: team) { (result) in
                                    completionHandler(result)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func register(_ app: ALTApplication, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let appName = app.name
        let bundleID = "com.\(team.identifier).\(app.bundleIdentifier)"
        
        ALTAppleAPI.shared.fetchAppIDs(for: team) { (appIDs, error) in
            do
            {
                let appIDs = try Result(appIDs, error).get()
                
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleID })
                {
                    completionHandler(.success(appID))
                }
                else
                {
                    ALTAppleAPI.shared.addAppID(withName: appName, bundleIdentifier: bundleID, team: team) { (appID, error) in
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
    
    func updateFeatures(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let requiredFeatures = app.entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = app.entitlements[.appGroups] as? [String], !applicationGroups.isEmpty
        {
            features[.appGroups] = true
        }
        
        let appID = appID.copy() as! ALTAppID
        appID.features = features
        
        ALTAppleAPI.shared.update(appID, team: team) { (appID, error) in
            completionHandler(Result(appID, error))
        }
    }
    
    func updateAppGroups(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
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
                
                ALTAppleAPI.shared.add(appID, to: group, team: team) { (success, error) in
                    let result = result.map { _ in appID }
                    completionHandler(result)
                }
            }
        }
        
        let adjustedGroupIdentifier = "group.\(team.identifier)." + groupIdentifier
        
        ALTAppleAPI.shared.fetchAppGroups(for: team) { (groups, error) in
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
                    
                    ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team) { (group, error) in
                        finish(Result(group, error))
                    }
                }
            }
        }
    }
    
    func fetchProvisioningProfile(for appID: ALTAppID, team: ALTTeam, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team) { (profile, error) in
            switch Result(profile, error)
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let profile):
                
                // Delete existing profile
                ALTAppleAPI.shared.delete(profile, for: team) { (success, error) in
                    switch Result(success, error)
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success:
                        
                        // Fetch new provisiong profile
                        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team) { (profile, error) in
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

                if self.context.bundleIdentifier == App.altstoreAppID
                {
                    guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
                    additionalValues[Bundle.Info.deviceID] = udid
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
