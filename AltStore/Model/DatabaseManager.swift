//
//  DatabaseManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import Roxas

public class DatabaseManager
{
    public static let shared = DatabaseManager()
    
    public let persistentContainer: RSTPersistentContainer
    
    public private(set) var isStarted = false
    
    private init()
    {
        self.persistentContainer = RSTPersistentContainer(name: "AltStore")
    }
}

public extension DatabaseManager
{
    func start(completionHandler: @escaping (Error?) -> Void)
    {
        guard !self.isStarted else { return completionHandler(nil) }
        
        self.persistentContainer.loadPersistentStores { (description, error) in
            guard error == nil else { return completionHandler(error!) }
            
            self.isStarted = true
            
            completionHandler(error)
        }
    }
    
    func signOut(completionHandler: @escaping (Error?) -> Void)
    {
        self.persistentContainer.performBackgroundTask { (context) in
            if let account = self.activeAccount(in: context)
            {
                account.isActiveAccount = false
            }
            
            if let team = self.activeTeam(in: context)
            {
                team.isActiveTeam = false
            }
            
            do
            {
                try context.save()
                
                Keychain.shared.reset()
                
                completionHandler(nil)
            }
            catch
            {
                print("Failed to save when signing out.", error)
                completionHandler(error)
            }
        }
    }
}

public extension DatabaseManager
{
    var viewContext: NSManagedObjectContext {
        return self.persistentContainer.viewContext
    }
}

extension DatabaseManager
{
    func activeAccount(in context: NSManagedObjectContext = DatabaseManager.shared.viewContext) -> Account?
    {
        let predicate = NSPredicate(format: "%K == YES", #keyPath(Account.isActiveAccount))
        
        let activeAccount = Account.first(satisfying: predicate, in: context)
        return activeAccount
    }
    
    func activeTeam(in context: NSManagedObjectContext = DatabaseManager.shared.viewContext) -> Team?
    {
        let predicate = NSPredicate(format: "%K == YES", #keyPath(Team.isActiveTeam))
        
        let activeTeam = Team.first(satisfying: predicate, in: context)
        return activeTeam
    }
}
