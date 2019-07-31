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
            assertionFailure("MergePolicy is only intended to work with database-level conflicts.")
            return try super.resolve(constraintConflicts: conflicts)            
        }
        
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as App:
                // Delete previous permissions
                for permission in databaseObject.permissions
                {
                    permission.managedObjectContext?.delete(permission)
                }
                
            case let databaseObject as Source:
                guard let conflictedObject = conflict.conflictingObjects.first as? Source else { break }

                let bundleIdentifiers = Set(conflictedObject.apps.map { $0.bundleIdentifier })

                for app in databaseObject.apps
                {
                    if !bundleIdentifiers.contains(app.bundleIdentifier)
                    {
                        // No longer listed in Source, so remove it from database.
                        app.managedObjectContext?.delete(app)
                    }
                }
                
            default: break
            }
        }
        
        try super.resolve(constraintConflicts: conflicts)
    }
}
