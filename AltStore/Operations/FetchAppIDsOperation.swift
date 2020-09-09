//
//  FetchAppIDsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAppIDsOperation)
class FetchAppIDsOperation: ResultOperation<([AppID], NSManagedObjectContext)>
{
    let context: AuthenticatedOperationContext
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AuthenticatedOperationContext, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.context = context
        self.managedObjectContext = managedObjectContext
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let team = self.context.team,
            let session = self.context.session
        else { return self.finish(.failure(OperationError.invalidParameters)) }
                
        ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { (appIDs, error) in
            self.managedObjectContext.perform {
                do
                {
                    let fetchedAppIDs = try Result(appIDs, error).get()
                    
                    guard let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), team.identifier), in: self.managedObjectContext) else { throw OperationError.notAuthenticated }
                    
                    let fetchedIdentifiers = fetchedAppIDs.map { $0.identifier }
                    
                    let deletedAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
                    deletedAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND NOT (%K IN %@)",
                                                                 #keyPath(AppID.team), team,
                                                                 #keyPath(AppID.identifier), fetchedIdentifiers)
                    
                    let deletedAppIDs = try self.managedObjectContext.fetch(deletedAppIDsRequest)
                    deletedAppIDs.forEach { self.managedObjectContext.delete($0) }
                    
                    let appIDs = fetchedAppIDs.map { AppID($0, team: team, context: self.managedObjectContext) }
                    self.finish(.success((appIDs, self.managedObjectContext)))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
    }
}
