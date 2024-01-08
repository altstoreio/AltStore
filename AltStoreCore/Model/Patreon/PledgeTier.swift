//
//  PledgeTier.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/24/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(PledgeTier)
public class PledgeTier: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var name: String?
    @NSManaged public private(set) var identifier: String
    
    @nonobjc public var amount: Decimal { _amount as Decimal } // In USD
    @NSManaged @objc(amount) private var _amount: NSDecimalNumber
    
    /* Relationships */
    @NSManaged public private(set) var pledge: Pledge?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(tier: PatreonAPI.Tier, context: NSManagedObjectContext)
    {
        super.init(entity: PledgeTier.entity(), insertInto: context)
        
        self.name = tier.name
        self.identifier = tier.identifier
        self._amount = tier.amount as NSDecimalNumber
    }
}

public extension PledgeTier
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PledgeTier>
    {
        return NSFetchRequest<PledgeTier>(entityName: "PledgeTier")
    }
}
