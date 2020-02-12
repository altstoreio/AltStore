//
//  FetchAppIDsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import AltKit

import Roxas

@objc(FetchAppIDsOperation)
class FetchAppIDsOperation: ResultOperation<([AppID], NSManagedObjectContext)>
{
    let group: OperationGroup
    let context: NSManagedObjectContext
    
    init(group: OperationGroup, context: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.group = group
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.group.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let team = self.group.signer?.team,
            let session = self.group.session
        else { return self.finish(.failure(OperationError.invalidParameters)) }
                
        ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { (appIDs, error) in
            self.context.perform {
                do
                {
                    let fetchedAppIDs = try Result(appIDs, error).get()
                    
                    guard let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), team.identifier), in: self.context) else { throw OperationError.notAuthenticated }
                    
                    let fetchedIdentifiers = fetchedAppIDs.map { $0.identifier }
                    
                    let deletedAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
                    deletedAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND NOT (%K IN %@)",
                                                                 #keyPath(AppID.team), team,
                                                                 #keyPath(AppID.identifier), fetchedIdentifiers)
                    
                    let deletedAppIDs = try self.context.fetch(deletedAppIDsRequest)
                    deletedAppIDs.forEach { self.context.delete($0) }
                    
                    let appIDs = fetchedAppIDs.map { AppID($0, team: team, context: self.context) }
                    self.finish(.success((appIDs, self.context)))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
    }
}
