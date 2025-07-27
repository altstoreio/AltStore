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

class UpdatePatronsOperation: ResultOperation<Void>, @unchecked Sendable
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
                if let response = response as? HTTPURLResponse
                {
                    guard response.statusCode != 404 else {
                        self.finish(.failure(URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: URL.patreonInfo])))
                        return
                    }
                }
                
                guard let data = data else { throw error! }
                
                let response = try AltStoreCore.JSONDecoder().decode(Response.self, from: data)
                Keychain.shared.patreonCreatorAccessToken = response.accessToken
                
                let previousRefreshID = UserDefaults.shared.patronsRefreshID
                guard response.refreshID != previousRefreshID && UserDefaults.shared.shouldFetchFriendZonePatrons else {
                    self.finish(.success(()))
                    return
                }
                
                PatreonAPI.shared.fetchPatrons { (result) in
                    self.context.perform {
                        do
                        {
                            let patrons = try result.get()
                            let managedPatrons = patrons.compactMap { ManagedPatron(patron: $0, context: self.context) }
                            
                            let patronIDs = Set(managedPatrons.map { $0.identifier })
                            let nonFriendZonePredicate = NSPredicate(format: "NOT (%K IN %@)", #keyPath(ManagedPatron.identifier), patronIDs)
                            
                            let nonFriendZonePatrons = ManagedPatron.all(satisfying: nonFriendZonePredicate, in: self.context)
                            for managedPatron in nonFriendZonePatrons
                            {
                                self.context.delete(managedPatron)
                            }
                            
                            try self.context.save()
                            
                            UserDefaults.shared.patronsRefreshID = response.refreshID
                            UserDefaults.shared.shouldFetchFriendZonePatrons = false // Disable fetching friend zone patrons until user navigates to Patreon screen again.
                            
                            self.finish(.success(()))
                            
                            Logger.main.notice("Updated Friend Zone Patrons! Refresh ID: \(response.refreshID, privacy: .public)")
                        }
                        catch let error as NSError
                        {
                            Logger.main.error("Failed to update Friend Zone Patrons. \(error.localizedDebugDescription ?? error.localizedDescription, privacy: .public)")
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
