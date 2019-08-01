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
    
    private var startCompletionHandlers = [(Error?) -> Void]()
    
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
        self.startCompletionHandlers.append(completionHandler)
        
        guard self.startCompletionHandlers.count == 1 else { return }
        
        func finish(_ error: Error?)
        {
            self.startCompletionHandlers.forEach { $0(error) }
            self.startCompletionHandlers.removeAll()
        }
        
        guard !self.isStarted else { return finish(nil) }
        
        self.persistentContainer.loadPersistentStores { (description, error) in
            guard error == nil else { return finish(error!) }
            
            self.prepareDatabase() { (result) in
                switch result
                {
                case .failure(let error):
                    finish(error)
                    
                case .success:
                    self.isStarted = true
                    finish(nil)
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
        let context = self.persistentContainer.newBackgroundContext()
        context.performAndWait {
            guard let localApp = ALTApplication(fileURL: Bundle.main.bundleURL) else { return }
            
            let storeApp: StoreApp
            
            if let app = StoreApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID), in: context)
            {
                storeApp = app
            }
            else
            {
                let source = Source.makeAltStoreSource(in: context)
                
                storeApp = StoreApp.makeAltStoreApp(in: context)
                storeApp.version = localApp.version
                storeApp.source = source
            }
            
            let installedApp: InstalledApp
            
            if let app = storeApp.installedApp
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: localApp, originalBundleIdentifier: StoreApp.altstoreAppID, context: context)
                installedApp.storeApp = storeApp
            }
            
            installedApp.version = localApp.version
            
            let fileURL = installedApp.fileURL
            
            if !FileManager.default.fileExists(atPath: fileURL.path)
            {
                do
                {
                    try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: fileURL)
                    
                    let infoPlistURL = fileURL.appendingPathComponent("Info.plist")
                    
                    // TODO: Copy to temporary location, modify it, _then_ copy to final destination.
                    guard var infoDictionary = Bundle.main.infoDictionary else { throw ALTError(.missingInfoPlist) }
                    infoDictionary[kCFBundleIdentifierKey as String] = StoreApp.altstoreAppID
                    try (infoDictionary as NSDictionary).write(to: infoPlistURL)
                }
                catch
                {
                    print("Failed to copy AltStore app bundle to its proper location.", error)
                    
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            if let provisioningProfile = localApp.provisioningProfile
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
