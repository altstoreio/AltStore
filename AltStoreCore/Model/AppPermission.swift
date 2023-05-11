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

@objc(AppPermission)
public class AppPermission: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged @objc(permissionType) public var type: ALTAppPermissionType
    @NSManaged public var usageDescription: String?
    
    @nonobjc public var permission: any ALTAppPermission {
        switch self.type
        {
        case .entitlement: return ALTEntitlement(rawValue: self._permission)
        case .privacy: return ALTAppPrivacyPermission(rawValue: self._permission)
        case .backgroundMode: return ALTAppBackgroundMode(rawValue: self._permission)
        @unknown default: return ALTEntitlement(rawValue: self._permission)
        }
    }
    @NSManaged @objc(permission) public private(set) var _permission: String
    
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
        case entitlement
        case backgroundMode = "background"
        case privacy
        
        case usageDescription
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext,
              let source = decoder.sourceContext?.source,
              let storeApp = decoder.sourceContext?.storeApp
        else { preconditionFailure("Decoder's userInfo must contain non-nil managedObjectContext, sourceContext.source, and sourceContext.storeApp") }
        
        super.init(entity: AppPermission.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.usageDescription = try container.decodeIfPresent(String.self, forKey: .usageDescription)
            
            if let entitlement = try container.decodeIfPresent(String.self, forKey: .entitlement)
            {
                // Entitlements don't require a usage description.
                
                self._permission = entitlement
                self.type = .entitlement
            }
            else if let backgroundMode = try container.decodeIfPresent(String.self, forKey: .backgroundMode)
            {
                // Background Modes MUST have a usage description.
                guard self.usageDescription != nil else { throw SourceError.missingPermissionUsageDescription(permission: backgroundMode, type: .backgroundMode, app: storeApp, source: source) }
                
                self._permission = backgroundMode
                self.type = .backgroundMode
            }
            else if let privacyType = try container.decodeIfPresent(String.self, forKey: .privacy)
            {
                // Privacy Types MUST have a usage description.
                guard self.usageDescription != nil else { throw SourceError.missingPermissionUsageDescription(permission: privacyType, type: .privacy, app: storeApp, source: source) }
                
                self._permission = privacyType
                self.type = .privacy
            }
            else
            {
                throw SourceError.unknownPermissionType(app: storeApp, source: source)
            }
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

extension AppPermission: Identifiable
{
    @objc
    public var localizedName: String {
        self.permission.localizedName ?? self.permission.rawValue
    }
}

public extension AppPermission
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppPermission>
    {
        return NSFetchRequest<AppPermission>(entityName: "AppPermission")
    }
}
