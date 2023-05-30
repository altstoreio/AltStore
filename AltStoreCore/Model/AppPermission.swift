//
//  AppPermission.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import UIKit

import AltSign

@objc(AppPermission) @dynamicMemberLookup
public class AppPermission: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public var type: ALTAppPermissionType
    
    // usageDescription must be non-optional for backwards compatibility,
    // so we store non-optional value and provide public accessor with optional return type.
    @nonobjc public var usageDescription: String? {
        get { _usageDescription.isEmpty ? nil : _usageDescription }
        set { _usageDescription = newValue ?? "" }
    }
    @NSManaged @objc(usageDescription) private var _usageDescription: String
    
    @nonobjc public var permission: any ALTAppPermission {
        switch self.type
        {
        case .entitlement: return ALTEntitlement(rawValue: self._permission)
        case .privacy: return ALTAppPrivacyPermission(rawValue: self._permission)
        default: return UnknownAppPermission(rawValue: self._permission)
        }
    }
    @NSManaged @objc(permission) private var _permission: String
    
    // Set by StoreApp.
    @NSManaged public var appBundleID: String?
    
    /* Relationships */
    @NSManaged public internal(set) var app: StoreApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case usageDescription
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppPermission.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self._permission = try container.decode(String.self, forKey: .name)
            self.usageDescription = try container.decodeIfPresent(String.self, forKey: .usageDescription)
            
            // Will be updated from StoreApp.
            self.type = .unknown
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

public extension AppPermission
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppPermission>
    {
        return NSFetchRequest<AppPermission>(entityName: "AppPermission")
    }
}

// @dynamicMemberLookup
public extension AppPermission
{
    // Convenience for accessing .permission properties.
    subscript<T>(dynamicMember keyPath: KeyPath<any ALTAppPermission, T>) -> T {
        get {
            return self.permission[keyPath: keyPath]
        }
    }
}
