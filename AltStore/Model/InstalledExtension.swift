//
//  InstalledExtension.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

@objc(InstalledExtension)
class InstalledExtension: NSManagedObject, InstalledAppProtocol
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var bundleIdentifier: String
    @NSManaged var resignedBundleIdentifier: String
    @NSManaged var version: String
    
    @NSManaged var refreshedDate: Date
    @NSManaged var expirationDate: Date
    @NSManaged var installedDate: Date
    
    /* Relationships */
    @NSManaged var parentApp: InstalledApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(resignedAppExtension: ALTApplication, originalBundleIdentifier: String, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledExtension.entity(), insertInto: context)
        
        self.name = resignedAppExtension.name
        self.bundleIdentifier = originalBundleIdentifier
        self.resignedBundleIdentifier = resignedAppExtension.bundleIdentifier
        
        self.version = resignedAppExtension.version

        if let provisioningProfile = resignedAppExtension.provisioningProfile
        {
            self.refreshedDate = provisioningProfile.creationDate
            self.expirationDate = provisioningProfile.expirationDate
        }
        else
        {
            self.refreshedDate = Date()
            self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        }
        
        self.installedDate = Date()
    }
}

extension InstalledExtension
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledExtension>
    {
        return NSFetchRequest<InstalledExtension>(entityName: "InstalledExtension")
    }
}
