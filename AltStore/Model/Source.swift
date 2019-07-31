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
}

@objc(Source)
class Source: NSManagedObject, Fetchable, Decodable
{
    /* Properties */
    @NSManaged var name: String
    @NSManaged var identifier: String
    @NSManaged var sourceURL: URL
    
    /* Relationships */
    @objc(apps) @NSManaged private(set) var _apps: NSOrderedSet
    
    @nonobjc var apps: [StoreApp] {
        get {
            return self._apps.array as! [StoreApp]
        }
        set {
            self._apps = NSOrderedSet(array: newValue)
        }
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case identifier
        case sourceURL
        case apps
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
        
        let apps = try container.decodeIfPresent([StoreApp].self, forKey: .apps) ?? []
        for (index, app) in apps.enumerated()
        {
            app.sortIndex = Int32(index)
        }
        
        context.insert(self)
        
        // Must assign after we're inserted into context.
        self._apps = NSMutableOrderedSet(array: apps)
        
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
        source.sourceURL = URL(string: "https://www.dropbox.com/s/6qi1vt6hsi88lv6/Apps-Dev.json?dl=1")!
        
        return source
    }
    
    class func fetchAltStoreSource(in context: NSManagedObjectContext) -> Source?
    {
        let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context)
        return source
    }
}
