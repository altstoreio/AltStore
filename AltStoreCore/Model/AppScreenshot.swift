//
//  AppScreenshot.swift
//  AltStoreCore
//
//  Created by Riley Testut on 9/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import CoreData

@objc(AppScreenshot)
public class AppScreenshot: NSManagedObject, Fetchable, Decodable
{
    /* Properties */
    @NSManaged public private(set) var imageURL: URL
    
    public private(set) var size: CGSize? {
        get {
            guard let width = self.width?.doubleValue, let height = self.height?.doubleValue else { return nil }
            return CGSize(width: width, height: height)
        }
        set {
            if let newValue
            {
                self.width = NSNumber(value: newValue.width)
                self.height = NSNumber(value: newValue.height)
            }
            else
            {
                self.width = nil
                self.height = nil
            }
        }
    }
    @NSManaged private var width: NSNumber?
    @NSManaged private var height: NSNumber?
    
    @NSManaged public internal(set) var appBundleID: String
    @NSManaged public internal(set) var sourceID: String
    
    /* Relationships */
    @NSManaged public internal(set) var app: StoreApp?
    
    private enum CodingKeys: String, CodingKey
    {
        case imageURL
        case width
        case height
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    internal init(imageURL: URL, size: CGSize?, context: NSManagedObjectContext)
    {
        super.init(entity: AppScreenshot.entity(), insertInto: context)
        
        self.imageURL = imageURL
        self.size = size
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppScreenshot.entity(), insertInto: context)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.imageURL = try container.decode(URL.self, forKey: .imageURL)
        
        self.width = try container.decodeIfPresent(Int16.self, forKey: .width).map { NSNumber(value: $0) }
        self.height = try container.decodeIfPresent(Int16.self, forKey: .height).map { NSNumber(value: $0) }
    }
}

public extension AppScreenshot
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppScreenshot>
    {
        return NSFetchRequest<AppScreenshot>(entityName: "AppScreenshot")
    }
}
