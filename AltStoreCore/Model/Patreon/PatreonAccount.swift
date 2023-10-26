//
//  PatreonAccount.swift
//  AltStore
//
//  Created by Riley Testut on 8/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

extension PatreonAPI
{
    struct AccountResponse: Decodable
    {
        struct Data: Decodable
        {
            struct Attributes: Decodable
            {
                var first_name: String?
                var full_name: String
            }
            
            var id: String
            var attributes: Attributes
        }
        
        var data: Data
        var included: [AnyResponse]?
    }
}

@objc(PatreonAccount)
public class PatreonAccount: NSManagedObject, Fetchable
{
    @NSManaged public var identifier: String
    
    @NSManaged public var name: String
    @NSManaged public var firstName: String?
    
    @NSManaged @objc(isPatron) public var isAltStorePatron: Bool
    
    /* Relationships */
    @nonobjc public var pledges: Set<Pledge> {
        return self._pledges as! Set<Pledge>
    }
    @NSManaged @objc(pledges) public internal(set) var _pledges: NSSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(response: PatreonAPI.AccountResponse, context: NSManagedObjectContext)
    {
        super.init(entity: PatreonAccount.entity(), insertInto: context)
        
        self.identifier = response.data.id
        self.name = response.data.attributes.full_name
        self.firstName = response.data.attributes.first_name
        
        var campaignsByID = [String: PatreonAPI.CampaignResponse]()
        var patronsByID = [String: PatreonAPI.PatronResponse]()
        var tiersByID = [String: PatreonAPI.TierResponse]()
        var benefitsByID = [String: PatreonAPI.BenefitResponse]()
        
        for response in response.included ?? []
        {
            switch response
            {
            case .campaign(let response): campaignsByID[response.id] = response
            case .patron(let response): patronsByID[response.id] = response
            case .tier(let response): tiersByID[response.id] = response
            case .benefit(let response): benefitsByID[response.id] = response
            case .unknown: break // Ignore
            }
        }
                
        let pledges = patronsByID.values.compactMap { patron -> Pledge? in
            guard let relationships = patron.relationships, let campaignID = relationships.campaign?.data, let tierIDs = relationships.currently_entitled_tiers?.data else { return nil }
            guard let campaign = campaignsByID[campaignID.id] else { return nil }
            
            guard patron.attributes.patron_status == "active_patron" else { return nil }
            
            let amount = Decimal(patron.attributes.currently_entitled_amount_cents ?? 0) / 100
            let rawTiers = tierIDs.compactMap { tiersByID[$0.id] }
            
            let tiers = rawTiers.map { tier in
                let tier = PledgeTier(response: tier, context: context)
                return tier
            }
            
            let rewards = rawTiers.flatMap { tier in
                let benefits = tier.relationships?.benefits.data.compactMap { benefitsByID[$0.id] } ?? []
                
                let rewards = benefits.map { PledgeReward(response: $0, context: context) }
                return rewards
            }
                        
            let pledge = Pledge(identifier: patron.id, amount: amount, campaignURL: campaign.attributes.url, context: context)
            pledge._tiers = NSSet(array: tiers)
            pledge._rewards = NSSet(array: rewards)
            return pledge
        }
        
        self._pledges = NSSet(array: pledges)
    }
}

public extension PatreonAccount
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PatreonAccount>
    {
        return NSFetchRequest<PatreonAccount>(entityName: "PatreonAccount")
    }
}

