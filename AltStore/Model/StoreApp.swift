//
//  StoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import Roxas
import AltSign

extension StoreApp
{
    #if ALPHA
    static let altstoreAppID = "com.rileytestut.AltStore.Alpha"
    static let alternativeAltStoreAppIDs: Set<String> = ["com.rileytestut.AltStore", "com.rileytestut.AltStore.Beta"]
    #elseif BETA
    static let altstoreAppID = "com.rileytestut.AltStore.Beta"
    static let alternativeAltStoreAppIDs: Set<String> = ["com.rileytestut.AltStore", "com.rileytestut.AltStore.Alpha"]
    #else
    static let altstoreAppID = "com.rileytestut.AltStore"
    static let alternativeAltStoreAppIDs: Set<String> = ["com.rileytestut.AltStore.Beta", "com.rileytestut.AltStore.Alpha"]
    #endif
    
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
}

@objc(StoreApp)
class StoreApp: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged private(set) var name: String
    @NSManaged private(set) var bundleIdentifier: String
    @NSManaged private(set) var subtitle: String?
    
    @NSManaged private(set) var developerName: String
    @NSManaged private(set) var localizedDescription: String
    @NSManaged private(set) var size: Int32
    
    @NSManaged private(set) var iconURL: URL
    @NSManaged private(set) var screenshotURLs: [URL]
    
    @NSManaged var version: String
    @NSManaged private(set) var versionDate: Date
    @NSManaged private(set) var versionDescription: String?
    
    @NSManaged private(set) var downloadURL: URL
    @NSManaged private(set) var tintColor: UIColor?
    @NSManaged private(set) var isBeta: Bool
    
    @NSManaged var sourceIdentifier: String?
    
    @NSManaged var sortIndex: Int32
    
    /* Relationships */
    @NSManaged var installedApp: InstalledApp?
    @NSManaged var newsItems: Set<NewsItem>
    
    @NSManaged @objc(source) var _source: Source?
    @NSManaged @objc(permissions) var _permissions: NSOrderedSet
    
    @nonobjc var source: Source? {
        set {
            self._source = newValue
            self.sourceIdentifier = newValue?.identifier
        }
        get {
            return self._source
        }
    }
    
    @nonobjc var permissions: [AppPermission] {
        return self._permissions.array as! [AppPermission]
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case bundleIdentifier
        case developerName
        case localizedDescription
        case version
        case versionDescription
        case versionDate
        case iconURL
        case screenshotURLs
        case downloadURL
        case tintColor
        case subtitle
        case permissions
        case size
        case isBeta = "beta"
    }
    
    required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: StoreApp.entity(), insertInto: nil)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.developerName = try container.decode(String.self, forKey: .developerName)
        self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
        
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        
        self.version = try container.decode(String.self, forKey: .version)
        self.versionDate = try container.decode(Date.self, forKey: .versionDate)
        self.versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
        
        self.iconURL = try container.decode(URL.self, forKey: .iconURL)
        self.screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? []
        
        self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        
        if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
        {
            guard let tintColor = UIColor(hexString: tintColorHex) else {
                throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
            }
            
            self.tintColor = tintColor
        }
        
        self.size = try container.decode(Int32.self, forKey: .size)
        self.isBeta = try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false
        
        let permissions = try container.decodeIfPresent([AppPermission].self, forKey: .permissions) ?? []
        
        context.insert(self)
        
        // Must assign after we're inserted into context.
        self._permissions = NSOrderedSet(array: permissions)
    }
}

extension StoreApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp>
    {
        return NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }
    
    class func makeAltStoreApp(in context: NSManagedObjectContext) -> StoreApp
    {
        let app = StoreApp(context: context)
        app.name = "AltStore"
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "Riley Testut"
        app.localizedDescription = "AltStore is an alternative App Store."
        app.iconURL = URL(string: "https://user-images.githubusercontent.com/705880/63392210-540c5980-c37b-11e9-968c-8742fc68ab2e.png")!
        app.screenshotURLs = []
        app.version = "1.0"
        app.versionDate = Date()
        app.downloadURL = URL(string: "http://rileytestut.com")!
        
        #if BETA
        app.isBeta = true
        #endif
        
        return app
    }
}
