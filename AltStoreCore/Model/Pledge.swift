//
//  Pledge.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/24/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

@objc(Pledge)
public class Pledge: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var identifier: String
    @NSManaged public private(set) var campaignURL: URL
    @NSManaged public private(set) var tierID: String?
    
    @nonobjc public var amount: Decimal {
        return (_amount ?? .zero) as Decimal
    }
    @objc(amount) private var _amount: NSDecimalNumber?
    
    /* Relationships */
    @nonobjc public var rewards: Set<PledgeReward> {
        return self._rewards as! Set<PledgeReward>
    }
    @NSManaged @objc(rewards) internal var _rewards: NSSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(identifier: String, amount: Decimal, campaignURL: URL, tierID: String?, context: NSManagedObjectContext)
    {
        super.init(entity: Pledge.entity(), insertInto: context)
        
        self.identifier = identifier
        self._amount = amount as NSDecimalNumber
        self.campaignURL = campaignURL
        self.tierID = tierID
    }
}

public extension Pledge
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Pledge>
    {
        return NSFetchRequest<Pledge>(entityName: "Pledge")
    }
}
