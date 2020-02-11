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

extension ALTTeamType
{
    var localizedDescription: String {
        switch self
        {
        case .free: return NSLocalizedString("Free Developer Account", comment: "")
        case .individual: return NSLocalizedString("Developer", comment: "")
        case .organization: return NSLocalizedString("Organization", comment: "")
        case .unknown: fallthrough
        @unknown default: return NSLocalizedString("Unknown", comment: "")
        }
    }
}

extension Team
{
    static let maximumFreeAppIDs = 10
}

@objc(Team)
class Team: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var identifier: String
    @NSManaged var type: ALTTeamType
    
    @NSManaged var isActiveTeam: Bool
    
    /* Relationships */
    @NSManaged private(set) var account: Account!
    @NSManaged var installedApps: Set<InstalledApp>
    @NSManaged private(set) var appIDs: Set<AppID>
    
    var altTeam: ALTTeam?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(_ team: ALTTeam, account: Account, context: NSManagedObjectContext)
    {
        super.init(entity: Team.entity(), insertInto: context)
        
        self.account = account
        
        self.update(team: team)
    }
    
    func update(team: ALTTeam)
    {
        self.altTeam = team
        
        self.name = team.name
        self.identifier = team.identifier
        self.type = team.type
    }
}

extension Team
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Team>
    {
        return NSFetchRequest<Team>(entityName: "Team")
    }
}
