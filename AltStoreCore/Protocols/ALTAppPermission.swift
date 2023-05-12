//
//  ALTAppPermission.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltSign

public extension ALTAppPermissionType
{
    var localizedName: String? {
        switch self
        {
        case .unknown: return NSLocalizedString("Permission", comment: "")
        case .entitlement: return NSLocalizedString("Entitlement", comment: "")
        case .privacy: return NSLocalizedString("Privacy Permission", comment: "")
        case .backgroundMode: return NSLocalizedString("Background Mode", comment: "")
        default: return nil
        }
    }
}

public protocol ALTAppPermission: RawRepresentable<String>, Hashable
{
    var type: ALTAppPermissionType { get }
    var symbolName: String? { get }
    
    var localizedName: String? { get }
    var localizedDisplayName: String { get } // Default implementation
}

public extension ALTAppPermission
{
    var localizedDisplayName: String {
        return self.localizedName ?? self.rawValue
    }
    
    func isEqual(_ permission: any ALTAppPermission) -> Bool
    {
        guard let permission = permission as? Self else { return false }
        return self == permission
    }
    
    static func ==(lhs: Self, rhs: any ALTAppPermission) -> Bool
    {
        return lhs.isEqual(rhs)
    }
}

public struct UnknownAppPermission: ALTAppPermission
{
    public var type: ALTAppPermissionType { .unknown }
    public var symbolName: String? { nil }
    
    public var localizedName: String? { nil }
        
    public var rawValue: String
    
    public init(rawValue: String)
    {
        self.rawValue = rawValue
    }
}

extension ALTEntitlement: ALTAppPermission
{
    public var type: ALTAppPermissionType { .entitlement }
    public var symbolName: String? { nil }
    
    public var localizedName: String? { nil }
}

extension ALTAppPrivacyPermission: ALTAppPermission
{
    public var type: ALTAppPermissionType { .privacy }
    public var symbolName: String? { nil }
    
    public var localizedName: String? { nil }
}

extension ALTAppBackgroundMode: ALTAppPermission
{
    public var type: ALTAppPermissionType { .backgroundMode }
    public var symbolName: String? { nil }
    
    public var localizedName: String? { nil }
}
