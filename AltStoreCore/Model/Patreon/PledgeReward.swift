//
//  PledgeReward.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/24/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(PledgeReward)
public class PledgeReward: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var name: String
    @NSManaged public private(set) var identifier: String
    
    /* Relationships */
    @NSManaged public private(set) var pledge: Pledge?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(benefit: PatreonAPI.Benefit, context: NSManagedObjectContext)
    {
        super.init(entity: PledgeReward.entity(), insertInto: context)
        
        self.name = benefit.name
        self.identifier = benefit.identifier.rawValue
    }
}

public extension PledgeReward
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PledgeReward>
    {
        return NSFetchRequest<PledgeReward>(entityName: "PledgeReward")
    }
}
