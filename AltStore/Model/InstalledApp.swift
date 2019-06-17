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
    
    @NSManaged var expirationDate: Date
    
    /* Relationships */
    @NSManaged private(set) var app: App!
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(app: App, bundleIdentifier: String, expirationDate: Date, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        let app = context.object(with: app.objectID) as! App
        self.app = app
        self.version = app.version
        
        self.bundleIdentifier = bundleIdentifier
        self.expirationDate = expirationDate
    }
}

extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
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
    
    class func ipaURL(for app: App) -> URL
    {
        let ipaURL = self.directoryURL(for: app).appendingPathComponent("App.ipa")
        return ipaURL
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
    
    var ipaURL: URL {
        return InstalledApp.ipaURL(for: self.app)
    }
    
    var refreshedIPAURL: URL {
        return InstalledApp.refreshedIPAURL(for: self.app)
    }
}
