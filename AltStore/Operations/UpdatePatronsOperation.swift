//
//  UpdatePatronsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/11/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore

private extension URL
{
    #if STAGING
    static let patreonInfo = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore/patreon.json")!
    #else
    static let patreonInfo = URL(string: "https://cdn.altstore.io/file/altstore/altstore/patreon.json")!
    #endif
}

extension UpdatePatronsOperation
{
    private struct Response: Decodable
    {
        var version: Int
        var accessToken: String
        var refreshID: String
    }
}

class UpdatePatronsOperation: ResultOperation<Void>
{
    let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        let dataTask = URLSession.shared.dataTask(with: .patreonInfo) { (data, response, error) in
            do
            {
                guard let data = data else { throw error! }
                
                let response = try AltStoreCore.JSONDecoder().decode(Response.self, from: data)
                
                let previousRefreshID = UserDefaults.shared.patronsRefreshID
                guard response.refreshID != previousRefreshID else {
                    self.finish(.success(()))
                    return
                }
                
                PatreonAPI.shared.fetchPatrons { (result) in
                    self.context.perform {
                        do
                        {
                            let patrons = try result.get()
                            let managedPatrons = patrons.map { (patron) -> PatreonAccount in
                                let account = PatreonAccount(patron: patron, context: self.context)
                                account.isFriendZonePatron = true
                                return account
                            }
                            
                            var patronIDs = Set(managedPatrons.map { $0.identifier })
                            if let userAccountID = Keychain.shared.patreonAccountID
                            {
                                // Insert userAccountID into patronIDs to prevent it from being deleted.
                                patronIDs.insert(userAccountID)
                            }
                                                
                            let removedPredicate = NSPredicate(format: "NOT (%K IN %@)", #keyPath(PatreonAccount.identifier), patronIDs)
                            let removedPatrons = PatreonAccount.all(satisfying: removedPredicate, in: self.context)
                            for patreonAccount in removedPatrons
                            {
                                self.context.delete(patreonAccount)
                            }
                            
                            try self.context.save()
                            
                            UserDefaults.shared.patronsRefreshID = response.refreshID
                            
                            self.finish(.success(()))
                            
                            print("Updated Friend Zone Patrons!")
                        }
                        catch
                        {
                            self.finish(.failure(error))
                        }
                    }
                }
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
        
        dataTask.resume()
    }
}
