//
//  PatreonAccount.swift
//  AltStore
//
//  Created by Riley Testut on 8/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

@objc(PatreonAccount)
public class PatreonAccount: NSManagedObject, Fetchable
{
    @NSManaged public var identifier: String
    
    @NSManaged public var name: String
    @NSManaged public var firstName: String?
    
    // Use `isPatron` for backwards compatibility.
    @NSManaged @objc(isPatron) public var isAltStorePatron: Bool
    
    /* Relationships */
    @nonobjc public var pledges: Set<Pledge> { _pledges as! Set<Pledge> }
    @NSManaged @objc(pledges) internal var _pledges: NSSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(account: PatreonAPI.UserAccount, context: NSManagedObjectContext)
    {
        super.init(entity: PatreonAccount.entity(), insertInto: context)
        
        self.identifier = account.identifier
        self.name = account.name
        self.firstName = account.firstName
        
        let pledges = account.pledges?.compactMap { patron -> Pledge? in
            // First ensure pledge is active.
            guard patron.status == .active else { return nil }
            
            guard let pledge = Pledge(patron: patron, context: context) else { return nil }
            
            let tiers = patron.tiers.map { PledgeTier(tier: $0, context: context) }
            pledge._tiers = Set(tiers) as NSSet
            
            let rewards = patron.benefits.map { PledgeReward(benefit: $0, context: context) }
            pledge._rewards = Set(rewards) as NSSet
            
            return pledge
        } ?? []
        
        self._pledges = Set(pledges) as NSSet
        
        if let altstorePledge = account.pledges?.first(where: { $0.campaign?.identifier == PatreonAPI.altstoreCampaignID })
        {
            let isActivePatron = (altstorePledge.status == .active)
            self.isAltStorePatron = isActivePatron
        }
        else
        {
            self.isAltStorePatron = false
        }
    }
}

public extension PatreonAccount
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PatreonAccount>
    {
        return NSFetchRequest<PatreonAccount>(entityName: "PatreonAccount")
    }
}

