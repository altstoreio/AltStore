//
//  Pledge.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/24/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(Pledge)
public class Pledge: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var identifier: String
    @NSManaged public private(set) var campaignURL: URL
    
    @nonobjc public var amount: Decimal { _amount as Decimal }
    @NSManaged @objc(amount) private var _amount: NSDecimalNumber
    
    /* Relationships */
    @NSManaged public private(set) var account: PatreonAccount?
    
    @nonobjc public var tiers: Set<PledgeTier> { _tiers as! Set<PledgeTier> }
    @NSManaged @objc(tiers) internal var _tiers: NSSet
    
    @nonobjc public var rewards: Set<PledgeReward> { _rewards as! Set<PledgeReward> }
    @NSManaged @objc(rewards) internal var _rewards: NSSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init?(patron: PatreonAPI.Patron, context: NSManagedObjectContext)
    {
        guard let amount = patron.pledgeAmount, let campaignURL = patron.campaign?.url else { return nil }
        
        super.init(entity: Pledge.entity(), insertInto: context)
        
        self.identifier = patron.identifier
        self._amount = amount as NSDecimalNumber
        self.campaignURL = campaignURL
    }
}

public extension Pledge
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Pledge>
    {
        return NSFetchRequest<Pledge>(entityName: "Pledge")
    }
}
