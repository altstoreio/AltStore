//
//  Team.swift
//  AltStore
//
//  Created by Riley Testut on 5/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

@objc(Team)
class Team: NSManagedObject
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var identifier: String
    @NSManaged var type: ALTTeamType
    
    /* Relationships */
    @NSManaged private(set) var account: Account!
    
    var altTeam: ALTTeam?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(_ team: ALTTeam, account: Account, context: NSManagedObjectContext)
    {
        super.init(entity: Team.entity(), insertInto: context)
        
        self.altTeam = team
        
        self.name = team.name
        self.identifier = team.identifier
        self.type = team.type
        
        self.account = account
    }
}

extension Team
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Team>
    {
        return NSFetchRequest<Team>(entityName: "Team")
    }
}
