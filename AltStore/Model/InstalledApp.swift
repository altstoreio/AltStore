//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

protocol InstalledAppProtocol: Fetchable
{
    var name: String { get }
    var bundleIdentifier: String { get }
    var resignedBundleIdentifier: String { get }
    var version: String { get }
    
    var refreshedDate: Date { get }
    var expirationDate: Date { get }
    var installedDate: Date { get }
}

@objc(InstalledApp)
class InstalledApp: NSManagedObject, InstalledAppProtocol
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var bundleIdentifier: String
    @NSManaged var resignedBundleIdentifier: String
    @NSManaged var version: String
    
    @NSManaged var refreshedDate: Date
    @NSManaged var expirationDate: Date
    @NSManaged var installedDate: Date
    
    /* Relationships */
    @NSManaged var storeApp: StoreApp?
    @NSManaged var team: Team?
    @NSManaged var appExtensions: Set<InstalledExtension>
    
    var isSideloaded: Bool {
        return self.storeApp == nil
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(resignedApp: ALTApplication, originalBundleIdentifier: String, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        
        self.update(resignedApp: resignedApp)
    }
    
    func update(resignedApp: ALTApplication)
    {
        self.name = resignedApp.name
        
        self.resignedBundleIdentifier = resignedApp.bundleIdentifier
        self.version = resignedApp.version

        if let provisioningProfile = resignedApp.provisioningProfile
        {
            self.refreshedDate = provisioningProfile.creationDate
            self.expirationDate = provisioningProfile.expirationDate
        }
    }
}

extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
    
    class func updatesFetchRequest() -> NSFetchRequest<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K != nil AND %K != %K", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.version), #keyPath(InstalledApp.storeApp.version))
        return fetchRequest
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        let altStore = InstalledApp.first(satisfying: predicate, in: context)
        return altStore
    }
    
    class func fetchAppsForRefreshingAll(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        var predicate = NSPredicate(format: "%K != %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
        {
            // No additional predicate
        }
        else
        {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
        }
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context)
        {
            // Refresh AltStore last since it causes app to quit.
            installedApps.append(altStoreApp)
        }
        
        return installedApps
    }
    
    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        // Date 6 hours before now.
        let date = Date().addingTimeInterval(-1 * 6 * 60 * 60)
        
        var predicate = NSPredicate(format: "(%K < %@) AND (%K != %@)",
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
        {
            // No additional predicate
        }
        else
        {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
        }
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context), altStoreApp.refreshedDate < date
        {
            // Refresh AltStore last since it causes app to quit.
            installedApps.append(altStoreApp)
        }
        
        return installedApps
    }
}

extension InstalledApp
{
    var openAppURL: URL {
        let openAppURL = URL(string: "altstore-" + self.bundleIdentifier + "://")!
        return openAppURL
    }
    
    class func openAppURL(for app: AppProtocol) -> URL
    {
        let openAppURL = URL(string: "altstore-" + app.bundleIdentifier + "://")!
        return openAppURL
    }
}

extension InstalledApp
{
    class var appsDirectoryURL: URL {
        let appsDirectoryURL = FileManager.default.applicationSupportDirectory.appendingPathComponent("Apps")
        
        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return appsDirectoryURL
    }
    
    class func fileURL(for app: AppProtocol) -> URL
    {
        let appURL = self.directoryURL(for: app).appendingPathComponent("App.app")
        return appURL
    }
    
    class func refreshedIPAURL(for app: AppProtocol) -> URL
    {
        let ipaURL = self.directoryURL(for: app).appendingPathComponent("Refreshed.ipa")
        return ipaURL
    }
    
    class func directoryURL(for app: AppProtocol) -> URL
    {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.bundleIdentifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return directoryURL
    }
    
    class func installedAppUTI(forBundleIdentifier bundleIdentifier: String) -> String
    {
        let installedAppUTI = "io.altstore.Installed." + bundleIdentifier
        return installedAppUTI
    }
    
    var directoryURL: URL {
        return InstalledApp.directoryURL(for: self)
    }
    
    var fileURL: URL {
        return InstalledApp.fileURL(for: self)
    }
    
    var refreshedIPAURL: URL {
        return InstalledApp.refreshedIPAURL(for: self)
    }
    
    var installedAppUTI: String {
        return InstalledApp.installedAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
}
