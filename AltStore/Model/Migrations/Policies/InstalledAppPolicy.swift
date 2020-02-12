//
//  InstalledAppPolicy.swift
//  AltStore
//
//  Created by Riley Testut on 1/24/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData

@objc(InstalledAppToInstalledAppMigrationPolicy)
class InstalledAppToInstalledAppMigrationPolicy: NSEntityMigrationPolicy
{
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
        
        // Entity must be in manager.destinationContext.
        let entity = NSEntityDescription.entity(forEntityName: "Team", in: manager.destinationContext)
        
        let fetchRequest = NSFetchRequest<NSManagedObject>()
        fetchRequest.entity = entity
        fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(Team.isActiveTeam))
        
        let teams = try manager.destinationContext.fetch(fetchRequest)
        
        // Cannot use NSManagedObject subclasses during migration, so fallback to using KVC instead.
        dInstance.setValue(teams.first, forKey: #keyPath(InstalledApp.team))
    }
}
