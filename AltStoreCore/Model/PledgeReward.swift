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
    
    @NSManaged public private(set) var pledgeID: String?
    
    /* Relationships */
    @nonobjc public private(set) var pledge: Pledge? {
        set {
            self._pledge = newValue
            self.pledgeID = newValue?.identifier
        }
        get {
            return self._pledge
        }
    }
    @objc(pledge) private var _pledge: Pledge?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(response: PatreonAPI.BenefitResponse, context: NSManagedObjectContext)
    {
        super.init(entity: PledgeReward.entity(), insertInto: context)
        
        self.name = response.attributes?.title ?? ""
        self.identifier = response.id
    }
}

public extension PledgeReward
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PledgeReward>
    {
        return NSFetchRequest<PledgeReward>(entityName: "PledgeReward")
    }
}
