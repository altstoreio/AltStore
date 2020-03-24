//
//  NewsItem.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import CoreData

@objc(NewsItem)
class NewsItem: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged var identifier: String
    @NSManaged var date: Date
    
    @NSManaged var title: String
    @NSManaged var caption: String
    @NSManaged var tintColor: UIColor
    @NSManaged var sortIndex: Int32
    @NSManaged var isSilent: Bool
    
    @NSManaged var imageURL: URL?
    @NSManaged var externalURL: URL?
    
    @NSManaged var appID: String?
    @NSManaged var sourceIdentifier: String?
    
    /* Relationships */
    @NSManaged var storeApp: StoreApp?
    @NSManaged var source: Source?
    
    private enum CodingKeys: String, CodingKey
    {
        case identifier
        case date
        case title
        case caption
        case tintColor
        case imageURL
        case externalURL = "url"
        case appID
        case notify
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: NewsItem.entity(), insertInto: context)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.date = try container.decode(Date.self, forKey: .date)
        
        self.title = try container.decode(String.self, forKey: .title)
        self.caption = try container.decode(String.self, forKey: .caption)
        
        if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
        {
            guard let tintColor = UIColor(hexString: tintColorHex) else {
                throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
            }
            
            self.tintColor = tintColor
        }
        
        self.imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        self.externalURL = try container.decodeIfPresent(URL.self, forKey: .externalURL)
        
        self.appID = try container.decodeIfPresent(String.self, forKey: .appID)
        
        let notify = try container.decodeIfPresent(Bool.self, forKey: .notify) ?? false
        self.isSilent = !notify
    }
}

extension NewsItem
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<NewsItem>
    {
        return NSFetchRequest<NewsItem>(entityName: "NewsItem")
    }
}
