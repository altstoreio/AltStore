//
//  InstalledAppPolicy.swift
//  AltStore
//
//  Created by Riley Testut on 1/24/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import AltSign

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
    
    @objc(defaultIsActiveForBundleID:team:)
    func defaultIsActive(for bundleID: String, team: NSManagedObject?) -> NSNumber
    {
        let isActive: Bool
        
        let activeAppsMinimumVersion = OperatingSystemVersion(majorVersion: 13, minorVersion: 3, patchVersion: 1)
        if !ProcessInfo.processInfo.isOperatingSystemAtLeast(activeAppsMinimumVersion)
        {
            isActive = true
        }
        else if let team = team, let type = team.value(forKey: #keyPath(Team.type)) as? Int16, type != ALTTeamType.free.rawValue
        {
            isActive = true
        }
        else
        {
            // AltStore should always be active, but deactivate all other apps.
            isActive = (bundleID == StoreApp.altstoreAppID)
            
            // We can assume there is an active app limit,
            // but will confirm next time user authenticates.
            UserDefaults.standard.activeAppsLimit = ALTActiveAppsLimit
        }
        
        return NSNumber(value: isActive)
    }
}
