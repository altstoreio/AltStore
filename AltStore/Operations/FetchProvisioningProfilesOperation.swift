//
//  FetchProvisioningProfilesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchProvisioningProfilesOperation)
class FetchProvisioningProfilesOperation: ResultOperation<[String: ALTProvisioningProfile]>
{
    let context: AppOperationContext
    
    var additionalEntitlements: [ALTEntitlement: Any]?
    
    private let appGroupsLock = NSLock()
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
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
            let team = self.context.team,
            let session = self.context.session
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        guard let app = self.context.app else { return self.finish(.failure(OperationError.appNotFound)) }
        
        self.progress.totalUnitCount = Int64(1 + app.appExtensions.count)
        
        self.prepareProvisioningProfile(for: app, parentApp: nil, team: team, session: session) { (result) in
            do
            {
                self.progress.completedUnitCount += 1
                
                let profile = try result.get()
                
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
                        
                        self.progress.completedUnitCount += 1
                    }
                }
                
                dispatchGroup.notify(queue: .global()) {
                    if let error = error
                    {
                        self.finish(.failure(error))
                    }
                    else
                    {
                        self.finish(.success(profiles))
                    }
                }
            }
            catch
            {
                self.finish(.failure(error))
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

extension FetchProvisioningProfilesOperation
{
    func prepareProvisioningProfile(for app: ALTApplication, parentApp: ALTApplication?, team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            
            let preferredBundleID: String?
            
            // Check if we have already installed this app with this team before.
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
            if let installedApp = InstalledApp.first(satisfying: predicate, in: context)
            {
                // Teams match if installedApp.team has same identifier as team,
                // or if installedApp.team is nil but resignedBundleIdentifier contains the team's identifier.
                let teamsMatch = installedApp.team?.identifier == team.identifier || (installedApp.team == nil && installedApp.resignedBundleIdentifier.contains(team.identifier))
                
                #if DEBUG
                
                if app.bundleIdentifier.hasPrefix(StoreApp.altstoreAppID) || StoreApp.alternativeAltStoreAppIDs.contains(where: app.bundleIdentifier.hasPrefix)
                {
                    // Use legacy bundle ID format for AltStore.
                    preferredBundleID = "com.\(team.identifier).\(app.bundleIdentifier)"
                }
                else
                {
                    preferredBundleID = teamsMatch ? installedApp.resignedBundleIdentifier : nil
                }
                
                #else
                
                if teamsMatch
                {
                    // This app is already installed with the same team, so use the same resigned bundle identifier as before.
                    // This way, if we change the identifier format (again), AltStore will continue to use
                    // the old bundle identifier to prevent it from installing as a new app.
                    preferredBundleID = installedApp.resignedBundleIdentifier
                }
                else
                {
                    preferredBundleID = nil
                }
                
                #endif
            }
            else
            {
                preferredBundleID = nil
            }
            
            let bundleID: String
            
            if let preferredBundleID = preferredBundleID
            {
                bundleID = preferredBundleID
            }
            else
            {
                // This app isn't already installed, so create the resigned bundle identifier ourselves.
                // Or, if the app _is_ installed but with a different team, we need to create a new
                // bundle identifier anyway to prevent collisions with the previous team.
                let parentBundleID = parentApp?.bundleIdentifier ?? app.bundleIdentifier
                let updatedParentBundleID: String
                
                if app.bundleIdentifier.hasPrefix(StoreApp.altstoreAppID) || StoreApp.alternativeAltStoreAppIDs.contains(where: app.bundleIdentifier.hasPrefix)
                {
                    // Use legacy bundle ID format for AltStore (and its extensions).
                    updatedParentBundleID = "com.\(team.identifier).\(parentBundleID)"
                }
                else
                {
                    updatedParentBundleID = parentBundleID + "." + team.identifier // Append just team identifier to make it harder to track.
                }
                
                bundleID = app.bundleIdentifier.replacingOccurrences(of: parentBundleID, with: updatedParentBundleID)
            }
            
            let preferredName: String
            
            if let parentApp = parentApp
            {
                preferredName = parentApp.name + " " + app.name
            }
            else
            {
                preferredName = app.name
            }
            
            // Register
            self.registerAppID(for: app, name: preferredName, bundleIdentifier: bundleID, team: team, session: session) { (result) in
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
                
                if let appID = appIDs.first(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() })
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
        var entitlements = app.entitlements
        for (key, value) in additionalEntitlements ?? [:]
        {
            entitlements[key] = value
        }
        
        let requiredFeatures = entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement: entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty
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
        var entitlements = app.entitlements
        for (key, value) in additionalEntitlements ?? [:]
        {
            entitlements[key] = value
        }
                
        var applicationGroups = entitlements[.appGroups] as? [String] ?? []
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
        
        if app.bundleIdentifier == StoreApp.altstoreAppID
        {
            // Updating app groups for this specific AltStore.
            // Find the (unique) AltStore app group, then replace it
            // with the correct "base" app group ID.
            // Otherwise, we may append a duplicate team identifier to the end.
            if let index = applicationGroups.firstIndex(where: { $0.contains(Bundle.baseAltStoreAppGroupID) })
            {
                applicationGroups[index] = Bundle.baseAltStoreAppGroupID
            }
            else
            {
                applicationGroups.append(Bundle.baseAltStoreAppGroupID)
            }
        }
        
        // Dispatch onto global queue to prevent appGroupsLock deadlock.
        DispatchQueue.global().async {
            
            // Ensure we're not concurrently fetching and updating app groups,
            // which can lead to race conditions such as adding an app group twice.
            self.appGroupsLock.lock()
            
            func finish(_ result: Result<ALTAppID, Error>)
            {
                self.appGroupsLock.unlock()
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
}
