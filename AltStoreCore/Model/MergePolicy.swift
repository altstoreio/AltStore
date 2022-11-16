//
//  MergePolicy.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import Roxas

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
                    
                    databaseObject.setVersions(sortedVersions)
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
                // Update versions post-merging to make sure latestSupportedVersion is correct.
                databaseObject.setVersions(databaseObject.versions)
                
            default: break
            }
        }
    }
}
