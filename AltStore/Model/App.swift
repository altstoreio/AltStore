//
//  App.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import Roxas

@objc(App)
class App: NSManagedObject, Decodable
{
    /* Properties */
    @NSManaged private(set) var name: String
    @NSManaged private(set) var identifier: String
    
    @NSManaged private(set) var developerName: String
    @NSManaged private(set) var localizedDescription: String
    
    @NSManaged private(set) var iconName: String
    @NSManaged private(set) var screenshotNames: [String]
    
    @NSManaged private(set) var version: String
    @NSManaged private(set) var versionDate: Date
    @NSManaged private(set) var versionDescription: String?
    
    @NSManaged private(set) var downloadURL: URL
    
    /* Relationships */
    @NSManaged private(set) var installedApp: InstalledApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case identifier
        case developerName
        case localizedDescription
        case version
        case versionDescription
        case versionDate
        case iconName
        case screenshotNames
        case downloadURL
    }
    
    required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: App.entity(), insertInto: nil)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.developerName = try container.decode(String.self, forKey: .developerName)
        self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
        
        self.version = try container.decode(String.self, forKey: .version)
        self.versionDate = try container.decode(Date.self, forKey: .versionDate)
        self.versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
        
        self.iconName = try container.decode(String.self, forKey: .iconName)
        self.screenshotNames = try container.decodeIfPresent([String].self, forKey: .screenshotNames) ?? []
        
        self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        
        context.insert(self)
    }
}

extension App
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<App>
    {
        return NSFetchRequest<App>(entityName: "App")
    }
}

extension App
{
    class var appsDirectoryURL: URL {
        let appsDirectoryURL = FileManager.default.applicationSupportDirectory.appendingPathComponent("Apps")
        
        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return appsDirectoryURL
    }
    
    var directoryURL: URL {
        let directoryURL = App.appsDirectoryURL.appendingPathComponent(self.identifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return directoryURL
    }
    
    var ipaURL: URL {
        let ipaURL = self.directoryURL.appendingPathComponent("App.ipa")
        return ipaURL
    }
}
