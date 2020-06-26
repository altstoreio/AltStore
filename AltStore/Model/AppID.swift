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
public class AppID: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var identifier: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var features: [ALTFeature: Any]
    @NSManaged public var expirationDate: Date?
    
    /* Relationships */
    @NSManaged public private(set) var team: Team?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(_ appID: ALTAppID, team: Team, context: NSManagedObjectContext)
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

public extension AppID
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppID>
    {
        return NSFetchRequest<AppID>(entityName: "AppID")
    }
}
