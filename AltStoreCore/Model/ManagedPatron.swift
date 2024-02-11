//
//  ManagedPatron.swift
//  AltStoreCore
//
//  Created by Riley Testut on 4/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

@objc(ManagedPatron)
public class ManagedPatron: NSManagedObject, Fetchable
{
    @NSManaged public var name: String
    @NSManaged public var identifier: String

    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init?(patron: PatreonAPI.Patron, context: NSManagedObjectContext)
    {
        // Only cache Patrons with non-nil names.
        guard let name = patron.name else { return nil }
        
        super.init(entity: ManagedPatron.entity(), insertInto: context)
        
        self.name = name
        self.identifier = patron.identifier
    }
}

public extension ManagedPatron
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<ManagedPatron>
    {
        return NSFetchRequest<ManagedPatron>(entityName: "Patron")
    }
}
