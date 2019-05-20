//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(InstalledApp)
class InstalledApp: NSManagedObject
{
    /* Properties */
    @NSManaged var bundleIdentifier: String
    @NSManaged var version: String
    
    @NSManaged var signedDate: Date
    @NSManaged var expirationDate: Date
    
    @NSManaged var isBeta: Bool
    
    /* Relationships */
    @NSManaged private(set) var app: App?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(app: App, bundleIdentifier: String, signedDate: Date, expirationDate: Date, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        let app = context.object(with: app.objectID) as! App
        self.app = app
        self.version = "0.9"
        
        self.bundleIdentifier = bundleIdentifier
        self.signedDate = signedDate
        self.expirationDate = expirationDate
    }
}

extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
}
