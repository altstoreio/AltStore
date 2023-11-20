//
//  MergePolicy.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import AltSign
import Roxas

extension MergeError
{
    public enum Code: Int, ALTErrorCode
    {
        public typealias Error = MergeError
        
        case noVersions
        case incorrectVersionOrder
        case incorrectPermissions
    }
    
    static func noVersions(for app: StoreApp) -> MergeError { .init(code: .noVersions, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
    static func incorrectVersionOrder(for app: StoreApp) -> MergeError { .init(code: .incorrectVersionOrder, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
    static func incorrectPermissions(for app: StoreApp) -> MergeError { .init(code: .incorrectPermissions, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
}

public struct MergeError: ALTLocalizedError
{
    public static var errorDomain: String { "AltStore.MergeError" }
    
    public let code: Code
    public var errorTitle: String?
    public var errorFailure: String?
    
    public var appName: String?
    public var appBundleID: String?
    public var sourceID: String?
    
    public var errorFailureReason: String {
        switch self.code
        {
        case .noVersions:
            var appName = NSLocalizedString("At least one app", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            
            return String(format: NSLocalizedString("%@ does not have any app versions.", comment: ""), appName)
            
        case .incorrectVersionOrder:
            var appName = NSLocalizedString("one or more apps", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            
            return String(format: NSLocalizedString("The cached versions for %@ do not match the source.", comment: ""), appName)
            
        case .incorrectPermissions:
            var appName = NSLocalizedString("one or more apps", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            
            return String(format: NSLocalizedString("The cached permissions for %@ do not match the source.", comment: ""), appName)
        }
    }
    
    public var recoverySuggestion: String? {
        switch self.code
        {
        case .incorrectVersionOrder: return NSLocalizedString("Please try again later.", comment: "")
        default: return nil
        }
    }
}

// Necessary to cast back to MergeError from NSError when thrown from NSMergePolicy.
extension MergeError: _ObjectiveCBridgeableError
{
    public var errorUserInfo: [String : Any] {
        // Copied from ALTLocalizedError
        var userInfo: [String: Any?] = [
            NSLocalizedFailureErrorKey: self.errorFailure,
            ALTLocalizedTitleErrorKey: self.errorTitle,
            ALTSourceFileErrorKey: self.sourceFile,
            ALTSourceLineErrorKey: self.sourceLine,
        ]
        
        userInfo["appName"] = self.appName
        userInfo["appBundleID"] = self.appBundleID
        userInfo["sourceID"] = self.sourceID
        
        return userInfo.compactMapValues { $0 }
    }
    
    public init?(_bridgedNSError error: NSError)
    {
        guard error.domain == MergeError.errorDomain, let code = Code(rawValue: error.code) else { return nil }
        
        self.code = code
        self.errorTitle = error.localizedTitle
        self.errorFailure = error.localizedFailure
        
        self.appName = error.userInfo["appName"] as? String
        self.appBundleID = error.userInfo["appBundleID"] as? String
        self.sourceID = error.userInfo["sourceID"] as? String
    }
}

private extension Error
{
    func serialized(withFailure failure: String) -> NSError
    {
        // We need to serialize Swift errors thrown during merge conflict to preserve error messages.
        
        let serializedError = (self as NSError).withLocalizedFailure(failure).sanitizedForSerialization()
        
        var userInfo = serializedError.userInfo
        userInfo[NSLocalizedDescriptionKey] = nil // Remove NSLocalizedDescriptionKey value to prevent duplicating localized failure in localized description.
        
        let error = NSError(domain: serializedError.domain, code: serializedError.code, userInfo: userInfo)
        return error
    }
}

open class MergePolicy: RSTRelationshipPreservingMergePolicy
{
    open override func resolve(constraintConflicts conflicts: [NSConstraintConflict]) throws
    {
        guard conflicts.allSatisfy({ $0.databaseObject != nil }) else {
            for conflict in conflicts
            {
                switch conflict.conflictingObjects.first
                {
                case is StoreApp where conflict.conflictingObjects.count == 2:
                    // Modified cached StoreApp while replacing it with new one, causing context-level conflict.
                    // Most likely, we set up a relationship between the new StoreApp and a NewsItem,
                    // causing cached StoreApp to delete it's NewsItem relationship, resulting in (resolvable) conflict.
                    
                    if let previousApp = conflict.conflictingObjects.first(where: { !$0.isInserted }) as? StoreApp
                    {
                        // Delete previous permissions (different than below).
                        for case let permission as AppPermission in previousApp._permissions where permission.app == nil
                        {
                            permission.managedObjectContext?.delete(permission)
                        }
                        
                        // Delete previous versions (different than below).
                        for case let appVersion as AppVersion in previousApp._versions where appVersion.app == nil
                        {
                            appVersion.managedObjectContext?.delete(appVersion)
                        }
                        
                        // Delete previous screenshots (different than below).
                        for case let appScreenshot as AppScreenshot in previousApp._screenshots where appScreenshot.app == nil
                        {
                            appScreenshot.managedObjectContext?.delete(appScreenshot)
                        }
                    }
                    
                case is AppVersion where conflict.conflictingObjects.count == 2:
                    // Occurs first time fetching sources after migrating from pre-AppVersion database model.
                    let conflictingAppVersions = conflict.conflictingObjects.lazy.compactMap { $0 as? AppVersion }
                    
                    // Primary AppVersion == AppVersion whose latestVersionApp.latestVersion points back to itself.
                    if let primaryAppVersion = conflictingAppVersions.first(where: { $0.latestSupportedVersionApp?.latestSupportedVersion == $0 }),
                       let secondaryAppVersion = conflictingAppVersions.first(where: { $0 != primaryAppVersion })
                    {
                        secondaryAppVersion.managedObjectContext?.delete(secondaryAppVersion)
                        print("[ALTLog] Resolving AppVersion context-level conflict. Most likely due to migrating from pre-AppVersion model version.", primaryAppVersion)
                    }
                    
                default:
                    // Unknown context-level conflict.
                    assertionFailure("MergePolicy is only intended to work with database-level conflicts.")
                }
            }
            
            try super.resolve(constraintConflicts: conflicts)
                        
            return
        }
        
        var permissionsByGlobalAppID = [String: Set<AnyHashable>]()
        var sortedVersionIDsByGlobalAppID = [String: NSOrderedSet]()
        var sortedScreenshotIDsByGlobalAppID = [String: NSOrderedSet]()
        
        var featuredAppIDsBySourceID = [String: [String]]()
        
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as StoreApp:
                guard let contextApp = conflict.conflictingObjects.first as? StoreApp else { break }
                
                // Permissions
                let contextPermissions = Set(contextApp._permissions.lazy.compactMap { $0 as? AppPermission }.map { AnyHashable($0.permission) })
                for case let databasePermission as AppPermission in databaseObject._permissions /* where !contextPermissions.contains(AnyHashable(databasePermission.permission)) */ // Compiler error as of Xcode 15
                {
                    if !contextPermissions.contains(AnyHashable(databasePermission.permission))
                    {
                        // Permission does NOT exist in context, so delete existing databasePermission.
                        databasePermission.managedObjectContext?.delete(databasePermission)
                    }
                }
                
                // Versions
                let contextVersionIDs = NSOrderedSet(array: contextApp._versions.lazy.compactMap { $0 as? AppVersion }.map { $0.versionID })
                for case let databaseVersion as AppVersion in databaseObject._versions where !contextVersionIDs.contains(databaseVersion.versionID)
                {
                    // Version # does NOT exist in context, so delete existing databaseVersion.
                    databaseVersion.managedObjectContext?.delete(databaseVersion)
                }
                
                // Screenshots
                let contextScreenshotIDs = NSOrderedSet(array: contextApp._screenshots.lazy.compactMap { $0 as? AppScreenshot }.map { $0.screenshotID })
                for case let databaseScreenshot as AppScreenshot in databaseObject._screenshots where !contextScreenshotIDs.contains(databaseScreenshot.screenshotID)
                {
                    // Screenshot ID does NOT exist in context, so delete existing databaseScreenshot.
                    databaseScreenshot.managedObjectContext?.delete(databaseScreenshot)
                }
                
                if let globallyUniqueID = contextApp.globallyUniqueID
                {
                    permissionsByGlobalAppID[globallyUniqueID] = contextPermissions
                    sortedVersionIDsByGlobalAppID[globallyUniqueID] = contextVersionIDs
                    sortedScreenshotIDsByGlobalAppID[globallyUniqueID] = contextScreenshotIDs
                }
                
            case let databaseObject as Source:
                guard let conflictedObject = conflict.conflictingObjects.first as? Source else { break }
                
                let bundleIdentifiers = Set(conflictedObject.apps.map { $0.bundleIdentifier })
                let newsItemIdentifiers = Set(conflictedObject.newsItems.map { $0.identifier })
                
                for app in databaseObject.apps
                {
                    if !bundleIdentifiers.contains(app.bundleIdentifier)
                    {
                        // No longer listed in Source, so remove it from database.
                        app.managedObjectContext?.delete(app)
                    }
                }
                
                for newsItem in databaseObject.newsItems
                {
                    if !newsItemIdentifiers.contains(newsItem.identifier)
                    {
                        // No longer listed in Source, so remove it from database.
                        newsItem.managedObjectContext?.delete(newsItem)
                    }
                }
                
                if let contextSource = conflict.conflictingObjects.first as? Source
                {
                    featuredAppIDsBySourceID[databaseObject.identifier] = contextSource.featuredApps?.map { $0.bundleIdentifier }
                }
                
            case let databasePledge as Pledge:
                guard let contextPledge = conflict.conflictingObjects.first as? Pledge else { break }
                
                // Tiers
                let contextTierIDs = Set(contextPledge._tiers.lazy.compactMap { $0 as? PledgeTier }.map { $0.identifier })
                for case let databaseTier as PledgeTier in databasePledge._tiers where !contextTierIDs.contains(databaseTier.identifier)
                {
                    // Tier ID does NOT exist in context, so delete existing databaseTier.
                    databaseTier.managedObjectContext?.delete(databaseTier)
                }
                
                // Rewards
                let contextRewardIDs = Set(contextPledge._rewards.lazy.compactMap { $0 as? PledgeReward }.map { $0.identifier })
                for case let databaseReward as PledgeReward in databasePledge._rewards where !contextRewardIDs.contains(databaseReward.identifier)
                {
                    // Reward ID does NOT exist in context, so delete existing databaseReward.
                    databaseReward.managedObjectContext?.delete(databaseReward)
                }
                
            case let databaseAccount as PatreonAccount:
                guard let contextAccount = conflict.conflictingObjects.first as? PatreonAccount else { break }
                
                let contextPledgeIDs = Set(contextAccount._pledges.lazy.compactMap { $0 as? Pledge }.map { $0.identifier })
                for case let databasePledge as Pledge in databaseAccount._pledges where !contextPledgeIDs.contains(databasePledge.identifier)
                {
                    // Pledge ID does NOT exist in context, so delete existing databasePledge.
                    databasePledge.managedObjectContext?.delete(databasePledge)
                }
                
            default: break
            }
        }
        
        try super.resolve(constraintConflicts: conflicts)
        
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as StoreApp:
                do
                {
                    var appVersions = databaseObject.versions
                    
                    if let globallyUniqueID = databaseObject.globallyUniqueID
                    {
                        // Permissions
                        if let appPermissions = permissionsByGlobalAppID[globallyUniqueID],
                           case let databasePermissions = Set(databaseObject.permissions.map({ AnyHashable($0.permission) })),
                           databasePermissions != appPermissions
                        {
                            // Sorting order doesn't matter, but elements themselves don't match so throw error.
                            throw MergeError.incorrectPermissions(for: databaseObject)
                        }
                        
                        // App versions
                        if let sortedAppVersionIDs = sortedVersionIDsByGlobalAppID[globallyUniqueID],
                           let sortedAppVersionsIDsArray = sortedAppVersionIDs.array as? [String],
                           case let databaseVersionIDs = databaseObject.versions.map({ $0.versionID }),
                           databaseVersionIDs != sortedAppVersionsIDsArray
                        {
                            // databaseObject.versions post-merge doesn't match contextApp.versions pre-merge, so attempt to fix by re-sorting.
                            
                            let fixedAppVersions = databaseObject.versions.sorted { (versionA, versionB) in
                                let indexA = sortedAppVersionIDs.index(of: versionA.versionID)
                                let indexB = sortedAppVersionIDs.index(of: versionB.versionID)
                                return indexA < indexB
                            }
                            
                            let appVersionIDs = fixedAppVersions.map { $0.versionID }
                            guard appVersionIDs == sortedAppVersionsIDsArray else {
                                // fixedAppVersions still doesn't match source's versions, so throw MergeError.
                                throw MergeError.incorrectVersionOrder(for: databaseObject)
                            }
                            
                            appVersions = fixedAppVersions
                        }
                        
                        // Screenshots
                        if let sortedScreenshotIDs = sortedScreenshotIDsByGlobalAppID[globallyUniqueID],
                           let sortedScreenshotIDsArray = sortedScreenshotIDs.array as? [String],
                           case let databaseScreenshotIDs = databaseObject.allScreenshots.map({ $0.screenshotID }),
                           databaseScreenshotIDs != sortedScreenshotIDsArray
                        {
                            // Screenshot order is incorrect, so attempt to fix by re-sorting.
                            let fixedScreenshots = databaseObject.allScreenshots.sorted { (screenshotA, screenshotB) in
                                let indexA = sortedScreenshotIDs.index(of: screenshotA.screenshotID)
                                let indexB = sortedScreenshotIDs.index(of: screenshotB.screenshotID)
                                return indexA < indexB
                            }
                            
                            let appScreenshotIDs = fixedScreenshots.map { $0.screenshotID }
                            if appScreenshotIDs == sortedScreenshotIDsArray
                            {
                                databaseObject.setScreenshots(fixedScreenshots)
                            }
                            else
                            {
                                // Screenshots are still not in correct order, but not worth throwing error so ignore.
                                print("Failed to re-sort screenshots into correct order. Expected:", sortedScreenshotIDsArray)
                            }
                        }
                    }
                    
                    // Always update versions post-merging to make sure latestSupportedVersion is correct.
                    try databaseObject.setVersions(appVersions)
                }
                catch
                {
                    let nsError = error.serialized(withFailure: NSLocalizedString("AltStore's database could not be saved.", comment: ""))
                    throw nsError
                }
                
            case let databaseObject as Source:
                guard let featuredAppIDs = featuredAppIDsBySourceID[databaseObject.identifier] else {
                    databaseObject.setFeaturedApps(nil)
                    break
                }
                
                let featuredApps: [StoreApp]?
                
                let databaseFeaturedAppIDs = databaseObject.featuredApps?.map { $0.bundleIdentifier }
                if databaseFeaturedAppIDs != featuredAppIDs
                {
                    let fixedFeaturedApps = databaseObject.apps.lazy.filter { featuredAppIDs.contains($0.bundleIdentifier) }.sorted { (appA, appB) in
                        let indexA = featuredAppIDs.firstIndex(of: appA.bundleIdentifier)!
                        let indexB = featuredAppIDs.firstIndex(of: appB.bundleIdentifier)!
                        return indexA < indexB
                    }
                    
                    featuredApps = fixedFeaturedApps
                }
                else
                {
                    featuredApps = databaseObject.featuredApps
                }
                
                // Update featuredApps post-merging to make sure relationships are correct,
                // even if the ordering is correct.
                databaseObject.setFeaturedApps(featuredApps)
                
            default: break
            }
        }
    }
}
