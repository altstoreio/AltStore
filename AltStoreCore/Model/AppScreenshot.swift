//
//  AppScreenshot.swift
//  AltStoreCore
//
//  Created by Riley Testut on 9/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import CoreData

import AltSign

public extension AppScreenshot
{
    static let defaultAspectRatio = CGSize(width: 9, height: 19.5)
}

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
    
    // Defaults to .iphone
    @nonobjc public var deviceType: ALTDeviceType {
        get { ALTDeviceType(rawValue: Int(_deviceType)) }
        set { _deviceType = Int16(newValue.rawValue) }
    }
    @NSManaged @objc(deviceType) private var _deviceType: Int16
    
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
    
    internal init(imageURL: URL, size: CGSize?, deviceType: ALTDeviceType, context: NSManagedObjectContext)
    {
        super.init(entity: AppScreenshot.entity(), insertInto: context)
        
        self.imageURL = imageURL
        self.size = size
        self.deviceType = deviceType
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
    
    public override func awakeFromInsert()
    {
        super.awakeFromInsert()
        
        self.deviceType = .iphone
    }
}

extension AppScreenshot
{
    var screenshotID: String {
        let screenshotID = "\(self.imageURL.absoluteString)|\(self.deviceType)"
        return screenshotID
    }
}

public extension AppScreenshot
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppScreenshot>
    {
        return NSFetchRequest<AppScreenshot>(entityName: "AppScreenshot")
    }
}

internal struct AppScreenshots: Decodable
{
    var screenshots: [AppScreenshot] = []
    
    enum CodingKeys: String, CodingKey
    {
        case iphone
        case ipad
    }
    
    init(from decoder: Decoder) throws
    {
        let container: KeyedDecodingContainer<CodingKeys>
                
        do
        {
            container = try decoder.container(keyedBy: CodingKeys.self)
        }
        catch DecodingError.typeMismatch
        {
            // ONLY catch the container's DecodingError.typeMismatch, not the below decodeIfPresent()'s
            
            // Fallback to single array.
            
            var collection = try Collection(from: decoder)
            collection.deviceType = .iphone
            
            self.screenshots = collection.screenshots
            
            return
        }
        
        if var collection = try container.decodeIfPresent(Collection.self, forKey: .iphone)
        {
            collection.deviceType = .iphone
            self.screenshots += collection.screenshots
        }
        
        if var collection = try container.decodeIfPresent(Collection.self, forKey: .ipad)
        {
            collection.deviceType = .ipad
            self.screenshots += collection.screenshots
        }
    }
}

extension AppScreenshots
{
    struct Collection: Decodable
    {
        var screenshots: [AppScreenshot] = []
        
        var deviceType: ALTDeviceType = .iphone {
            didSet {
                self.screenshots.forEach { $0.deviceType = self.deviceType }
            }
        }
        
        init(from decoder: Decoder) throws
        {
            guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
            
            var container = try decoder.unkeyedContainer()
            
            while !container.isAtEnd
            {
                do
                {
                    // Attempt parsing as URL first.
                    let imageURL = try container.decode(URL.self)
                    
                    let screenshot = AppScreenshot(imageURL: imageURL, size: nil, deviceType: self.deviceType, context: context)
                    self.screenshots.append(screenshot)
                }
                catch DecodingError.typeMismatch
                {
                    // Fall back to parsing full AppScreenshot (preferred).
                    
                    let screenshot = try container.decode(AppScreenshot.self)
                    self.screenshots.append(screenshot)
                }
            }
        }
    }
}
