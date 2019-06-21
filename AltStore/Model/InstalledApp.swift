//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(InstalledApp)
class InstalledApp: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged var bundleIdentifier: String
    @NSManaged var version: String
    
    @NSManaged var refreshedDate: Date
    @NSManaged var expirationDate: Date
    
    /* Relationships */
    @NSManaged private(set) var app: App!
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(app: App, bundleIdentifier: String, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        let app = context.object(with: app.objectID) as! App
        self.app = app
        self.version = app.version
        
        self.bundleIdentifier = bundleIdentifier
        
        self.refreshedDate = Date()
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
    }
}

extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.app.identifier), App.altstoreAppID)
        
        let altStore = InstalledApp.first(satisfying: predicate, in: context)
        return altStore
    }
    
    class func fetchAppsForRefreshingAll(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        let predicate = NSPredicate(format: "%K != %@", #keyPath(InstalledApp.app.identifier), App.altstoreAppID)
        
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
        let date = Date().addingTimeInterval(-120)
        
        let predicate = NSPredicate(format: "(%K < %@) AND (%K != %@)",
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.app.identifier), App.altstoreAppID)
        
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
        // Don't use the actual bundle ID yet since we're hardcoding support for the first apps in AltStore.
        let openAppURL = URL(string: "altstore-" + self.app.identifier + "://")!
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
    
    class func fileURL(for app: App) -> URL
    {
        let appURL = self.directoryURL(for: app).appendingPathComponent("App.app")
        return appURL
    }
    
    class func refreshedIPAURL(for app: App) -> URL
    {
        let ipaURL = self.directoryURL(for: app).appendingPathComponent("Refreshed.ipa")
        return ipaURL
    }
    
    class func directoryURL(for app: App) -> URL
    {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.identifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return directoryURL
    }
    
    var directoryURL: URL {
        return InstalledApp.directoryURL(for: self.app)
    }
    
    var fileURL: URL {
        return InstalledApp.fileURL(for: self.app)
    }
    
    var refreshedIPAURL: URL {
        return InstalledApp.refreshedIPAURL(for: self.app)
    }
}
