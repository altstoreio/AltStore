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

public extension ALTTeamType
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

public extension Team
{
    static let maximumFreeAppIDs = 10
}

@objc(Team)
public class Team: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var identifier: String
    @NSManaged public var type: ALTTeamType
    
    @NSManaged public var isActiveTeam: Bool
    
    /* Relationships */
    @NSManaged public private(set) var account: Account!
    @NSManaged public var installedApps: Set<InstalledApp>
    @NSManaged public private(set) var appIDs: Set<AppID>
    
    public var altTeam: ALTTeam?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(_ team: ALTTeam, account: Account, context: NSManagedObjectContext)
    {
        super.init(entity: Team.entity(), insertInto: context)
        
        self.account = account
        
        self.update(team: team)
    }
    
    public func update(team: ALTTeam)
    {
        self.altTeam = team
        
        self.name = team.name
        self.identifier = team.identifier
        self.type = team.type
    }
}

public extension Team
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Team>
    {
        return NSFetchRequest<Team>(entityName: "Team")
    }
}
