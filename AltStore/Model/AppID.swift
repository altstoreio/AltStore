//
//  AppID.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

@objc(AppID)
class AppID: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var identifier: String
    @NSManaged var bundleIdentifier: String
    @NSManaged var features: [ALTFeature: Any]
    @NSManaged var expirationDate: Date?
    
    /* Relationships */
    @NSManaged private(set) var team: Team?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(_ appID: ALTAppID, team: Team, context: NSManagedObjectContext)
    {
        super.init(entity: AppID.entity(), insertInto: context)
                
        self.name = appID.name
        self.identifier = appID.identifier
        self.bundleIdentifier = appID.bundleIdentifier
        self.features = appID.features
        self.expirationDate = appID.expirationDate
        
        self.team = team
    }
}

extension AppID
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppID>
    {
        return NSFetchRequest<AppID>(entityName: "AppID")
    }
}
