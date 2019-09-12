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
        var included: [PatronResponse]?
    }
}

@objc(PatreonAccount)
class PatreonAccount: NSManagedObject, Fetchable
{
    @NSManaged var identifier: String
    
    @NSManaged var name: String
    @NSManaged var firstName: String?
    
    @NSManaged var isPatron: Bool
    
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
        
        if let patronResponse = response.included?.first
        {
            let patron = Patron(response: patronResponse)
            self.isPatron = (patron.status == .active)
        }
        else
        {
            self.isPatron = false
        }
    }
}

extension PatreonAccount
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PatreonAccount>
    {
        return NSFetchRequest<PatreonAccount>(entityName: "PatreonAccount")
    }
}

