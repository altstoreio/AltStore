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

extension CFNotificationName
{
    fileprivate static let willMigrateDatabase = CFNotificationName("com.rileytestut.AltStore.WillMigrateDatabase" as CFString)
}

private let ReceivedWillMigrateDatabaseNotification: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
    DatabaseManager.shared.receivedWillMigrateDatabaseNotification()
}

fileprivate class PersistentContainer: RSTPersistentContainer, @unchecked Sendable
{
    override class func defaultDirectoryURL() -> URL
    {
        guard let sharedDirectoryURL = FileManager.default.altstoreSharedDirectory else { return super.defaultDirectoryURL() }
        
        let databaseDirectoryURL = sharedDirectoryURL.appendingPathComponent("Database")
        try? FileManager.default.createDirectory(at: databaseDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        return databaseDirectoryURL
    }
    
    class func legacyDirectoryURL() -> URL
    {
        return super.defaultDirectoryURL()
    }
}

public class DatabaseManager
{
    public static let shared = DatabaseManager()
    
    public let persistentContainer: RSTPersistentContainer
    
    public private(set) var isStarted = false
    
    private var startCompletionHandlers = [(Error?) -> Void]()
    private let dispatchQueue = DispatchQueue(label: "io.altstore.DatabaseManager")
    
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    private var ignoreWillMigrateDatabaseNotification = false
    
    private init()
    {
        self.persistentContainer = PersistentContainer(name: "AltStore", bundle: Bundle(for: DatabaseManager.self))
        self.persistentContainer.preferredMergePolicy = MergePolicy()
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, ReceivedWillMigrateDatabaseNotification, CFNotificationName.willMigrateDatabase.rawValue, nil, .deliverImmediately)
    }
}

public extension DatabaseManager
{
    func start(completionHandler: @escaping (Error?) -> Void)
    {
        func finish(_ error: Error?)
        {
            self.dispatchQueue.async {
                if error == nil
                {
                    self.isStarted = true
                }
                
                self.startCompletionHandlers.forEach { $0(error) }
                self.startCompletionHandlers.removeAll()
            }
        }
        
        self.dispatchQueue.async {
            self.startCompletionHandlers.append(completionHandler)
            guard self.startCompletionHandlers.count == 1 else { return }
            
            guard !self.isStarted else { return finish(nil) }
            
            #if DEBUG
            // Wrap in #if DEBUG to *ensure* we never accidentally delete production databases.
            if ProcessInfo.processInfo.isPreview
            {
                do
                {
                    print("!!! Purging database for preview...")
                    try FileManager.default.removeItem(at: PersistentContainer.defaultDirectoryURL())
                }
                catch
                {
                    print("Failed to remove database directory for preview.", error)
                }
            }
            #endif
            
            if self.persistentContainer.isMigrationRequired
            {
                // Quit any other running AltStore processes to prevent concurrent database access during and after migration.
                self.ignoreWillMigrateDatabaseNotification = true
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), .willMigrateDatabase, nil, nil, true)
            }
            
            self.migrateDatabaseToAppGroupIfNeeded { (result) in
                switch result
                {
                case .failure(let error): finish(error)
                case .success:
                    self.persistentContainer.loadPersistentStores { (description, error) in
                        guard error == nil else { return finish(error!) }
                        
                        self.prepareDatabase() { (result) in
                            switch result
                            {
                            case .failure(let error): finish(error)
                            case .success: finish(nil)
                            }
                        }
                    }
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
    
    func purgeLoggedErrors(before date: Date? = nil, completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.persistentContainer.performBackgroundTask { context in
            do
            {
                let predicate = date.map { NSPredicate(format: "%K <= %@", #keyPath(LoggedError.date), $0 as NSDate) }
                
                let loggedErrors = LoggedError.all(satisfying: predicate, in: context, requestProperties: [\.returnsObjectsAsFaults: true])
                loggedErrors.forEach { context.delete($0) }
                
                try context.save()
                
                completion(.success(()))
            }
            catch
            {
                completion(.failure(error))
            }
        }
    }
    
    func updateFeaturedSortIDs() async
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy // DON'T use our custom merge policy, because that one ignores changes to featuredSortID.
        await context.performAsync {
            do
            {
                // Randomize source order
                let fetchRequest = Source.fetchRequest()
                let sources = try context.fetch(fetchRequest)
                
                for source in sources
                {
                    source.featuredSortID = UUID().uuidString
                }
                
                try context.save()
            }
            catch
            {
                Logger.main.error("Failed to update source order. \(error.localizedDescription, privacy: .public)")
            }
            
            do
            {
                // Randomize app order
                let fetchRequest = StoreApp.fetchRequest()
                let apps = try context.fetch(fetchRequest)
                
                for app in apps
                {
                    app.featuredSortID = UUID().uuidString
                }
                
                try context.save()
            }
            catch
            {
                Logger.main.error("Failed to update app order. \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

public extension DatabaseManager
{
    func startForPreview()
    {
        let semaphore = DispatchSemaphore(value: 0)
        
        self.dispatchQueue.async {
            self.startCompletionHandlers.append { error in
                semaphore.signal()
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
}

public extension DatabaseManager
{
    var viewContext: NSManagedObjectContext {
        return self.persistentContainer.viewContext
    }
    
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
        guard let patreonAccountID = Keychain.shared.patreonAccountID else { return nil }
            
        let predicate = NSPredicate(format: "%K == %@", #keyPath(PatreonAccount.identifier), patreonAccountID)
        
        let patreonAccount = PatreonAccount.first(satisfying: predicate, in: context, requestProperties: [\.relationshipKeyPathsForPrefetching: [#keyPath(PatreonAccount._pledges)]])
        return patreonAccount
    }
}

private extension DatabaseManager
{
    func prepareDatabase(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        guard !Bundle.isAppExtension() else { return completionHandler(.success(())) }
        
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
            try! altStoreSource.setSourceURL(Source.altStoreSourceURL)
            
            #if MARKETPLACE
            
            let storeBuildVersion = localApp.buildVersion
            
            #else
            
            //TODO: Support build versions.
            // For backwards compatibility reasons, we cannot use localApp's buildVersion as storeBuildVersion,
            // or else the latest update will _always_ be considered new because we don't use buildVersions in our source (yet).
            let storeBuildVersion: String? = nil
            
            #endif
            
            let storeApp: StoreApp
            
            if let app = StoreApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID), in: context)
            {
                storeApp = app
            }
            else
            {
                storeApp = StoreApp.makeAltStoreApp(version: localApp.version, buildVersion: storeBuildVersion, in: context)
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
                installedApp = InstalledApp(resignedApp: localApp, originalBundleIdentifier: StoreApp.altstoreAppID, certificateSerialNumber: serialNumber, storeBuildVersion: storeBuildVersion, context: context)
                installedApp.storeApp = storeApp
            }
            
            /* App Extensions */
            var installedExtensions = Set<InstalledExtension>()
            
            for appExtension in localApp.appExtensions
            {
                let resignedBundleID = appExtension.bundleIdentifier
                let originalBundleID = resignedBundleID.replacingOccurrences(of: localApp.bundleIdentifier, with: StoreApp.altstoreAppID)
                
                let installedExtension: InstalledExtension
                
                if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == originalBundleID })
                {
                    installedExtension = appExtension
                }
                else
                {
                    installedExtension = InstalledExtension(resignedAppExtension: appExtension, originalBundleIdentifier: originalBundleID, context: context)
                }
                
                installedExtension.update(resignedAppExtension: appExtension)
                
                installedExtensions.insert(installedExtension)
            }
            
            installedApp.appExtensions = installedExtensions
            
            let fileURL = installedApp.fileURL
            
            #if DEBUG
            let replaceCachedApp = true
            #else
            let replaceCachedApp = !FileManager.default.fileExists(atPath: fileURL.path) || installedApp.version != localApp.version || installedApp.buildVersion != localApp.buildVersion
            #endif
            
            if replaceCachedApp
            {
                func update(_ bundle: Bundle, bundleID: String) throws
                {
                    let infoPlistURL = bundle.bundleURL.appendingPathComponent("Info.plist")
                    
                    guard var infoDictionary = bundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }
                    infoDictionary[kCFBundleIdentifierKey as String] = bundleID
                    try (infoDictionary as NSDictionary).write(to: infoPlistURL)
                }
                
                FileManager.default.prepareTemporaryURL() { (temporaryFileURL) in
                    do
                    {
                        try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: temporaryFileURL)
                        
                        guard let appBundle = Bundle(url: temporaryFileURL) else { throw ALTError(.invalidApp) }
                        try update(appBundle, bundleID: StoreApp.altstoreAppID)
                        
                        if let tempApp = ALTApplication(fileURL: temporaryFileURL)
                        {
                            for appExtension in tempApp.appExtensions
                            {
                                guard let extensionBundle = Bundle(url: appExtension.fileURL) else { throw ALTError(.invalidApp) }
                                guard let installedExtension = installedExtensions.first(where: { $0.resignedBundleIdentifier == appExtension.bundleIdentifier }) else { throw ALTError(.invalidApp) }
                                try update(extensionBundle, bundleID: installedExtension.bundleIdentifier)
                            }
                        }
                        
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
            installedApp.update(resignedApp: localApp, certificateSerialNumber: serialNumber, storeBuildVersion: storeBuildVersion)
            
            // DON'T override app version with ALTVersion now that source versions must match CFBundleShortVersionString.
            // if let version = Bundle.main.object(forInfoDictionaryKey: "ALTVersion") as? String
            // {
            //     // Override app version if ALTVersion key exists.
            //     installedApp.version = version
            // }
            
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
                
                Task(priority: .high) {
                    await self.updateFeaturedSortIDs()
                    completionHandler(.success(()))
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func migrateDatabaseToAppGroupIfNeeded(completion: @escaping (Result<Void, Error>) -> Void)
    {
        // Only migrate if we haven't migrated yet and there's a valid AltStore app group.
        guard UserDefaults.shared.requiresAppGroupMigration && Bundle.main.altstoreAppGroup != nil else { return completion(.success(())) }

        func finish(_ result: Result<Void, Error>)
        {
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success:
                UserDefaults.shared.requiresAppGroupMigration = false
                completion(.success(()))
            }
        }
        
        let previousDatabaseURL = PersistentContainer.legacyDirectoryURL().appendingPathComponent("AltStore.sqlite")
        let databaseURL = PersistentContainer.defaultDirectoryURL().appendingPathComponent("AltStore.sqlite")
        
        let previousAppsDirectoryURL = InstalledApp.legacyAppsDirectoryURL
        let appsDirectoryURL = InstalledApp.appsDirectoryURL
        
        let databaseIntent = NSFileAccessIntent.writingIntent(with: databaseURL, options: [.forReplacing])
        let appsIntent = NSFileAccessIntent.writingIntent(with: appsDirectoryURL, options: [.forReplacing])
        
        self.coordinator.coordinate(with: [databaseIntent, appsIntent], queue: self.coordinatorQueue) { (error) in
            do
            {
                if let error = error
                {
                    throw error
                }
                
                let description = NSPersistentStoreDescription(url: previousDatabaseURL)
                
                // Disable WAL to remove extra files automatically during migration.
                description.setOption(["journal_mode": "DELETE"] as NSDictionary, forKey: NSSQLitePragmasOption)
                
                let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.persistentContainer.managedObjectModel)
                
                // Migrate database
                if FileManager.default.fileExists(atPath: previousDatabaseURL.path)
                {
                    if FileManager.default.fileExists(atPath: databaseURL.path, isDirectory: nil)
                    {
                        try FileManager.default.removeItem(at: databaseURL)
                    }
                    
                    let previousDatabase = try persistentStoreCoordinator.addPersistentStore(ofType: description.type, configurationName: description.configuration, at: description.url, options: description.options)
                    
                    // Pass nil options to prevent later error due to self.persistentContainer using WAL.
                    try persistentStoreCoordinator.migratePersistentStore(previousDatabase, to: databaseURL, options: nil, withType: NSSQLiteStoreType)
                    
                    try FileManager.default.removeItem(at: previousDatabaseURL)
                }
                
                // Migrate apps
                if FileManager.default.fileExists(atPath: previousAppsDirectoryURL.path, isDirectory: nil)
                {
                    _ = try FileManager.default.replaceItemAt(appsDirectoryURL, withItemAt: previousAppsDirectoryURL)
                }
                
                finish(.success(()))
            }
            catch
            {
                print("Failed to migrate database to app group:", error)
                finish(.failure(error))
            }
        }
    }
    
    func receivedWillMigrateDatabaseNotification()
    {
        defer { self.ignoreWillMigrateDatabaseNotification = false }
        
        // Ignore notifications sent by the current process.
        guard !self.ignoreWillMigrateDatabaseNotification else { return }
        
        exit(104)
    }
}
