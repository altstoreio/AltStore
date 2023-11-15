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
    
    @NSManaged public var isPatron: Bool
    
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
        
        if let altstorePledge = account.pledges?.first(where: { $0.campaign?.identifier == PatreonAPI.altstoreCampaignID })
        {
            let isActivePatron = (altstorePledge.status == .active)
            self.isPatron = isActivePatron
        }
        else
        {
            self.isPatron = false
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

