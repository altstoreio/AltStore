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
public class Account: NSManagedObject, Fetchable
{
    public var localizedName: String {
        var components = PersonNameComponents()
        components.givenName = self.firstName
        components.familyName = self.lastName
        
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name
    }
    
    /* Properties */
    @NSManaged public var appleID: String
    @NSManaged public var identifier: String
    
    @NSManaged public var firstName: String
    @NSManaged public var lastName: String
    
    @NSManaged public var isActiveAccount: Bool
    
    /* Relationships */
    @NSManaged public var teams: Set<Team>
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(_ account: ALTAccount, context: NSManagedObjectContext)
    {
        super.init(entity: Account.entity(), insertInto: context)
        
        self.update(account: account)
    }
    
    public func update(account: ALTAccount)
    {
        self.appleID = account.appleID
        self.identifier = account.identifier
        
        self.firstName = account.firstName
        self.lastName = account.lastName
    }
}

public extension Account
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Account>
    {
        return NSFetchRequest<Account>(entityName: "Account")
    }
}
