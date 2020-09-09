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
public class InstalledExtension: NSManagedObject, InstalledAppProtocol
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var version: String
    
    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date
    
    /* Relationships */
    @NSManaged public var parentApp: InstalledApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(resignedAppExtension: ALTApplication, originalBundleIdentifier: String, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledExtension.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        
        self.update(resignedAppExtension: resignedAppExtension)
    }
    
    public func update(resignedAppExtension: ALTApplication)
    {
        self.name = resignedAppExtension.name
        
        self.resignedBundleIdentifier = resignedAppExtension.bundleIdentifier
        self.version = resignedAppExtension.version

        if let provisioningProfile = resignedAppExtension.provisioningProfile
        {
            self.update(provisioningProfile: provisioningProfile)
        }
    }
    
    public func update(provisioningProfile: ALTProvisioningProfile)
    {
        self.refreshedDate = provisioningProfile.creationDate
        self.expirationDate = provisioningProfile.expirationDate
    }
}

public extension InstalledExtension
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledExtension>
    {
        return NSFetchRequest<InstalledExtension>(entityName: "InstalledExtension")
    }
}
