//
//  App.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(App)
class App: NSManagedObject, Decodable
{
    /* Properties */
    @NSManaged private(set) var name: String
    @NSManaged private(set) var identifier: String
    
    @NSManaged private(set) var developerName: String
    @NSManaged private(set) var localizedDescription: String
    
    @NSManaged private(set) var iconName: String
    @NSManaged private(set) var screenshotNames: [String]
    
    /* Relationships */
    @NSManaged private(set) var installedApp: InstalledApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case identifier
        case developerName
        case localizedDescription
        case iconName
        case screenshotNames
    }
    
    required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: App.entity(), insertInto: nil)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.developerName = try container.decode(String.self, forKey: .developerName)
        self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
        
        self.iconName = try container.decode(String.self, forKey: .iconName)
        self.screenshotNames = try container.decodeIfPresent([String].self, forKey: .screenshotNames) ?? []
        
        context.insert(self)
    }
}



extension App
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<App>
    {
        return NSFetchRequest<App>(entityName: "App")
    }
}
