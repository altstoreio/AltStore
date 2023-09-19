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
    @NSManaged public var imageURL: URL
    
    @nonobjc public var width: Int? {
        return _width?.intValue
    }
    @NSManaged @objc(width) var _width: NSNumber?
    
    @nonobjc public var height: Int? {
        return _height?.intValue
    }
    @NSManaged @objc(height) var _height: NSNumber?
    
    public var size: CGSize? {
        guard let width = self.width, let height = self.height else { return nil }
        return CGSize(width: Double(width), height: Double(height))
    }
    
    @NSManaged public var isRounded: Bool
    @NSManaged public var isiPhone: Bool
    
    @NSManaged public var appBundleID: String
    @NSManaged public var sourceID: String
    
    // Relationships
    @NSManaged public var app: StoreApp?
    
    private enum CodingKeys: String, CodingKey
    {
        case imageURL
        case width
        case height
        case device
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(imageURL: URL, size: CGSize?, context: NSManagedObjectContext)
    {
        super.init(entity: AppScreenshot.entity(), insertInto: context)
        
        self.imageURL = imageURL
        
        if let size
        {
            self._width = NSNumber(value: size.width)
            self._height = NSNumber(value: size.height)
        }
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppScreenshot.entity(), insertInto: context)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.imageURL = try container.decode(URL.self, forKey: .imageURL)
        
        self._width = try container.decodeIfPresent(Int16.self, forKey: .width).map { NSNumber(value: $0) }
        self._height = try container.decodeIfPresent(Int16.self, forKey: .height).map { NSNumber(value: $0) }
    }
    
//    public init(identifier: String, result: Result<[String: Result<InstalledApp, Error>], Error>, context: NSManagedObjectContext)
//    {
//        super.init(entity: RefreshAttempt.entity(), insertInto: context)
//        
//        self.identifier = identifier
//        self.date = Date()
//        
//        do
//        {
//            let results = try result.get()
//            
//            for (_, result) in results
//            {
//                guard case let .failure(error) = result else { continue }
//                throw error
//            }
//            
//            self.isSuccess = true
//            self.errorDescription = nil
//        }
//        catch
//        {
//            self.isSuccess = false
//            self.errorDescription = error.localizedDescription
//        }
//    }
}

public extension AppScreenshot
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppScreenshot>
    {
        return NSFetchRequest<AppScreenshot>(entityName: "AppScreenshot")
    }
}
