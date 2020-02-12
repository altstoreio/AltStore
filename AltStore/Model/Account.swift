//
//  Account.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

@objc(Account)
class Account: NSManagedObject, Fetchable
{
    var localizedName: String {
        var components = PersonNameComponents()
        components.givenName = self.firstName
        components.familyName = self.lastName
        
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name
    }
    
    /* Properties */
    @NSManaged var appleID: String
    @NSManaged var identifier: String
    
    @NSManaged var firstName: String
    @NSManaged var lastName: String
    
    @NSManaged var isActiveAccount: Bool
    
    /* Relationships */
    @NSManaged var teams: Set<Team>
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(_ account: ALTAccount, context: NSManagedObjectContext)
    {
        super.init(entity: Account.entity(), insertInto: context)
        
        self.update(account: account)
    }
    
    func update(account: ALTAccount)
    {
        self.appleID = account.appleID
        self.identifier = account.identifier
        
        self.firstName = account.firstName
        self.lastName = account.lastName
    }
}

extension Account
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Account>
    {
        return NSFetchRequest<Account>(entityName: "Account")
    }
}
