//
//  MergePolicy.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import Roxas

extension MergeError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = MergeError
        
        case noVersions
    }
    
    static func noVersions(for app: AppProtocol) -> MergeError { .init(code: .noVersions, appName: app.name, appBundleID: app.bundleIdentifier) }
}

struct MergeError: ALTLocalizedError
{
    static var errorDomain: String { "AltStore.MergeError" }
    
    let code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    var appName: String?
    var appBundleID: String?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .noVersions:
            var appName = NSLocalizedString("At least one app", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            
            return String(format: NSLocalizedString("%@ does not have any app versions.", comment: ""), appName)
        }
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
                    let databaseVersions = Set(databaseObject._versions.lazy.compactMap { $0 as? AppVersion }.map { $0.version })
                    let sortIndexesByVersion = contextApp._versions.lazy.compactMap { $0 as? AppVersion }.reduce(into: [:]) { $0[$1.version] = contextApp._versions.index(of: $1)  }
                    let contextVersions = sortIndexesByVersion.keys
                    
                    var mergedVersions = Set<AppVersion>()
                    
                    for case let appVersion as AppVersion in databaseObject._versions
                    {
                        if contextVersions.contains(appVersion.version)
                        {
                            // Version # exists in context, so add existing appVersion to mergedVersions.
                            mergedVersions.insert(appVersion)
                        }
                        else
                        {
                            // Version # does NOT exist in context, so delete existing appVersion.
                            appVersion.managedObjectContext?.delete(appVersion)
                        }
                    }
                    
                    for case let appVersion as AppVersion in contextApp._versions where !databaseVersions.contains(appVersion.version)
                    {
                        // Add context appVersion only if version # doesn't already exist in databaseVersions.
                        mergedVersions.insert(appVersion)
                    }
                    
                    // Make sure versions are sorted in correct order.
                    let sortedVersions = mergedVersions.sorted { (versionA, versionB) in
                        let indexA = sortIndexesByVersion[versionA.version] ?? .max
                        let indexB = sortIndexesByVersion[versionB.version] ?? .max
                        return indexA < indexB
                    }
                    
                    do
                    {
                        try databaseObject.setVersions(sortedVersions)
                    }
                    catch
                    {
                        let nsError = error.serialized(withFailure: NSLocalizedString("AltStore's database could not be saved.", comment: ""))
                        throw nsError
                    }
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
                    // Update versions post-merging to make sure latestSupportedVersion is correct.
                    try databaseObject.setVersions(databaseObject.versions)
                }
                catch
                {
                    let nsError = error.serialized(withFailure: NSLocalizedString("AltStore's database could not be saved.", comment: ""))
                    throw nsError
                }
                
            default: break
            }
        }
    }
}
