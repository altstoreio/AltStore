//
//  DatabaseManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import AltSign
import Roxas

public class DatabaseManager
{
    public static let shared = DatabaseManager()
    
    public let persistentContainer: RSTPersistentContainer
    
    public private(set) var isStarted = false
    
    private init()
    {
        self.persistentContainer = RSTPersistentContainer(name: "AltStore")
        self.persistentContainer.preferredMergePolicy = MergePolicy()
    }
}

public extension DatabaseManager
{
    func start(completionHandler: @escaping (Error?) -> Void)
    {
        guard !self.isStarted else { return completionHandler(nil) }
        
        self.persistentContainer.loadPersistentStores { (description, error) in
            guard error == nil else { return completionHandler(error!) }
            
            self.prepareDatabase() { (result) in
                switch result
                {
                case .failure(let error): completionHandler(error)
                case .success:
                    self.isStarted = true
                    completionHandler(nil)
                }
            }
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

private extension DatabaseManager
{
    func prepareDatabase(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.persistentContainer.performBackgroundTask { (context) in
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            
            let altStoreApp: App
            
            if let app = App.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(App.identifier), App.altstoreAppID), in: context)
            {
                altStoreApp = app
            }
            else
            {
                altStoreApp = App.makeAltStoreApp(in: context)
                altStoreApp.version = version
            }
            
            let installedApp: InstalledApp
            
            if let app = altStoreApp.installedApp
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(app: altStoreApp, bundleIdentifier: altStoreApp.identifier, context: context)
            }
            
            installedApp.version = version
            
            if let provisioningProfileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let provisioningProfile = ALTProvisioningProfile(url: provisioningProfileURL)
            {
                installedApp.refreshedDate = provisioningProfile.creationDate
                installedApp.expirationDate = provisioningProfile.expirationDate
            }
            
            do
            {
                try context.save()
                completionHandler(.success(()))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
}
