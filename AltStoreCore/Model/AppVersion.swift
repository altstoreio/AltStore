//
//  AppVersion.swift
//  AltStoreCore
//
//  Created by Riley Testut on 8/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

@objc(AppVersion)
public class AppVersion: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public var version: String
    @NSManaged public var date: Date
    @NSManaged public var localizedDescription: String?
    
    @NSManaged public var downloadURL: URL
    @NSManaged public var size: Int64
    
    @nonobjc public var minOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._minOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(minOSVersion) private var _minOSVersion: String?
    
    @nonobjc public var maxOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._maxOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(maxOSVersion) private var _maxOSVersion: String?
    
    @NSManaged public var appBundleID: String
    @NSManaged public var sourceID: String?
    
    /* Relationships */
    @NSManaged public private(set) var app: StoreApp?
    @NSManaged @objc(latestVersionApp) public internal(set) var latestSupportedVersionApp: StoreApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case version
        case date
        case localizedDescription
        case downloadURL
        case size
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppVersion.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.version = try container.decode(String.self, forKey: .version)
            self.date = try container.decode(Date.self, forKey: .date)
            self.localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
            
            self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
            self.size = try container.decode(Int64.self, forKey: .size)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

public extension AppVersion
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppVersion>
    {
        return NSFetchRequest<AppVersion>(entityName: "AppVersion")
    }
    
    class func makeAppVersion(
        version: String,
        date: Date,
        localizedDescription: String? = nil,
        downloadURL: URL,
        size: Int64,
        appBundleID: String,
        sourceID: String? = nil,
        in context: NSManagedObjectContext) -> AppVersion
    {
        let appVersion = AppVersion(context: context)
        appVersion.version = version
        appVersion.date = date
        appVersion.localizedDescription = localizedDescription
        appVersion.downloadURL = downloadURL
        appVersion.size = size
        appVersion.appBundleID = appBundleID
        appVersion.sourceID = sourceID

        return appVersion
    }
    
    var isSupported: Bool {
        return true
    }
}
