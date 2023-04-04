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
    }
    
    static func noVersions(for app: StoreApp) -> MergeError { .init(code: .noVersions, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
    static func incorrectVersionOrder(for app: StoreApp) -> MergeError { .init(code: .incorrectVersionOrder, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
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
                        // Delete previous permissions (same as below).
                        for permission in previousApp.permissions
                        {
                            permission.managedObjectContext?.delete(permission)
                        }
                        
                        // Delete previous versions (different than below).
                        for case let appVersion as AppVersion in previousApp._versions where appVersion.app == nil
                        {
                            appVersion.managedObjectContext?.delete(appVersion)
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
        
        var sortedVersionsByAppBundleID = [String: NSOrderedSet]()
        var featuredAppIDsBySourceID = [String: [String]]()
        
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as StoreApp:
                // Delete previous permissions
                for permission in databaseObject.permissions
                {
                    permission.managedObjectContext?.delete(permission)
                }
                
                if let contextApp = conflict.conflictingObjects.first as? StoreApp
                {
                    let contextVersions = NSOrderedSet(array: contextApp._versions.lazy.compactMap { $0 as? AppVersion }.map { $0.version })

                    for case let appVersion as AppVersion in databaseObject._versions where !contextVersions.contains(appVersion.version)
                    {
                        // Version # does NOT exist in context, so delete existing appVersion.
                        appVersion.managedObjectContext?.delete(appVersion)
                    }
                    
                    // Core Data _normally_ preserves the correct ordering of versions when merging,
                    // but just in case we cache the order and reorder the versions post-merge if needed.
                    sortedVersionsByAppBundleID[databaseObject.bundleIdentifier] = contextVersions
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
                    let appVersions: [AppVersion]
                    
                    if let sortedAppVersions = sortedVersionsByAppBundleID[databaseObject.bundleIdentifier],
                       let sortedAppVersionsArray = sortedAppVersions.array as? [String],
                       case let databaseVersions = databaseObject.versions.map({ $0.version }),
                       databaseVersions != sortedAppVersionsArray
                    {
                        // databaseObject.versions post-merge doesn't match contextApp.versions pre-merge, so attempt to fix by re-sorting.
                        
                        let fixedAppVersions = databaseObject.versions.sorted { (versionA, versionB) in
                            let indexA = sortedAppVersions.index(of: versionA.version)
                            let indexB = sortedAppVersions.index(of: versionB.version)
                            return indexA < indexB
                        }
                        
                        let appVersionValues = fixedAppVersions.map { $0.version }
                        guard appVersionValues == sortedAppVersionsArray else {
                            // fixedAppVersions still doesn't match source's versions, so throw MergeError.
                            throw MergeError.incorrectVersionOrder(for: databaseObject)
                        }
                        
                        appVersions = fixedAppVersions
                    }
                    else
                    {
                        appVersions = databaseObject.versions
                    }
                    
                    // Update versions post-merging to make sure latestSupportedVersion is correct.
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
