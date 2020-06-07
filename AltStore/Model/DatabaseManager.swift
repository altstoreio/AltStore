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
    
    func patreonAccount(in context: NSManagedObjectContext = DatabaseManager.shared.viewContext) -> PatreonAccount?
    {
        let patronAccount = PatreonAccount.first(in: context)
        return patronAccount
    }
}

private extension DatabaseManager
{
    func prepareDatabase(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let context = self.persistentContainer.newBackgroundContext()
        context.performAndWait {
            guard let localApp = ALTApplication(fileURL: Bundle.main.bundleURL) else { return }
            
            let altStoreSource: Source
            
            if let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context)
            {
                altStoreSource = source
            }
            else
            {
                altStoreSource = Source.makeAltStoreSource(in: context)
            }
            
            // Make sure to always update source URL to be current.
            altStoreSource.sourceURL = Source.altStoreSourceURL
            
            let storeApp: StoreApp
            
            if let app = StoreApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID), in: context)
            {
                storeApp = app
            }
            else
            {
                storeApp = StoreApp.makeAltStoreApp(in: context)
                storeApp.version = localApp.version
                storeApp.source = altStoreSource
            }
                        
            let serialNumber = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.certificateID) as? String
            let installedApp: InstalledApp
            
            if let app = storeApp.installedApp
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: localApp, originalBundleIdentifier: StoreApp.altstoreAppID, certificateSerialNumber: serialNumber, context: context)
                installedApp.storeApp = storeApp
            }
            
            let fileURL = installedApp.fileURL
            
            #if DEBUG
            let replaceCachedApp = true
            #else
            let replaceCachedApp = !FileManager.default.fileExists(atPath: fileURL.path) || installedApp.version != localApp.version
            #endif
            
            if replaceCachedApp
            {
                FileManager.default.prepareTemporaryURL() { (temporaryFileURL) in
                    do
                    {
                        try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: temporaryFileURL)
                        
                        let infoPlistURL = temporaryFileURL.appendingPathComponent("Info.plist")
                        
                        guard var infoDictionary = Bundle.main.infoDictionary else { throw ALTError(.missingInfoPlist) }
                        infoDictionary[kCFBundleIdentifierKey as String] = StoreApp.altstoreAppID
                        try (infoDictionary as NSDictionary).write(to: infoPlistURL)
                        
                        try FileManager.default.copyItem(at: temporaryFileURL, to: fileURL, shouldReplace: true)
                    }
                    catch
                    {
                        print("Failed to copy AltStore app bundle to its proper location.", error)
                    }
                }
            }
            
            let cachedRefreshedDate = installedApp.refreshedDate
            let cachedExpirationDate = installedApp.expirationDate
                        
            // Must go after comparing versions to see if we need to update our cached AltStore app bundle.
            installedApp.update(resignedApp: localApp, certificateSerialNumber: serialNumber)
            
            if installedApp.refreshedDate < cachedRefreshedDate
            {
                // Embedded provisioning profile has a creation date older than our refreshed date.
                // This most likely means we've refreshed the app since then, and profile is now outdated,
                // so use cached dates instead (i.e. not the dates updated from provisioning profile).
                
                installedApp.refreshedDate = cachedRefreshedDate
                installedApp.expirationDate = cachedExpirationDate
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
