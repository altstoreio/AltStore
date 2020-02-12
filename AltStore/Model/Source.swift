//
//  Source.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

extension Source
{
    static let altStoreIdentifier = "com.rileytestut.AltStore"
    
    #if STAGING
    static let altStoreSourceURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/apps-staging.json")!
    #else
    static let altStoreSourceURL = URL(string: "https://cdn.altstore.io/file/altstore/apps.json")!
    #endif
}

@objc(Source)
class Source: NSManagedObject, Fetchable, Decodable
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var identifier: String
    @NSManaged var sourceURL: URL
    
    /* Non-Core Data Properties */
    var userInfo: [ALTSourceUserInfoKey: String]?
    
    /* Relationships */
    @objc(apps) @NSManaged private(set) var _apps: NSOrderedSet
    @objc(newsItems) @NSManaged private(set) var _newsItems: NSOrderedSet
    
    @nonobjc var apps: [StoreApp] {
        get {
            return self._apps.array as! [StoreApp]
        }
        set {
            self._apps = NSOrderedSet(array: newValue)
        }
    }
    
    @nonobjc var newsItems: [NewsItem] {
        get {
            return self._newsItems.array as! [NewsItem]
        }
        set {
            self._newsItems = NSOrderedSet(array: newValue)
        }
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case identifier
        case sourceURL
        case userInfo
        case apps
        case news
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: Source.entity(), insertInto: nil)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        
        let userInfo = try container.decodeIfPresent([String: String].self, forKey: .userInfo)
        self.userInfo = userInfo?.reduce(into: [:]) { $0[ALTSourceUserInfoKey($1.key)] = $1.value }
        
        let apps = try container.decodeIfPresent([StoreApp].self, forKey: .apps) ?? []
        for (index, app) in apps.enumerated()
        {
            app.sortIndex = Int32(index)
        }
        
        let newsItems = try container.decodeIfPresent([NewsItem].self, forKey: .news) ?? []
        for (index, item) in newsItems.enumerated()
        {
            item.sortIndex = Int32(index)
        }
        
        context.insert(self)
        
        let appsByID = Dictionary(apps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { (a, b) in return a })
        
        for newsItem in newsItems
        {
            newsItem.source = self
            
            guard let appID = newsItem.appID else { continue }
            
            if let storeApp = appsByID[appID]
            {
                newsItem.storeApp = storeApp
            }
        }
        
        // Must assign after we're inserted into context.
        self._apps = NSMutableOrderedSet(array: apps)
        self._newsItems = NSMutableOrderedSet(array: newsItems)
        
        print("Downloaded Order:", self.apps.map { $0.bundleIdentifier })
    }
}

extension Source
{
    class func makeAltStoreSource(in context: NSManagedObjectContext) -> Source
    {
        let source = Source(context: context)
        source.name = "AltStore"
        source.identifier = Source.altStoreIdentifier
        source.sourceURL = Source.altStoreSourceURL
        
        return source
    }
    
    class func fetchAltStoreSource(in context: NSManagedObjectContext) -> Source?
    {
        let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context)
        return source
    }
}
