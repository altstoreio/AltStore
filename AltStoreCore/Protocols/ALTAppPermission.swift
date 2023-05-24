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
    var localizedDescription: String? { get }
    
    // Default implementations
    var effectiveSymbolName: String { get }
    var localizedDisplayName: String { get }
}

public extension ALTAppPermission
{
    var effectiveSymbolName: String { self.symbolName ?? "lock" }
    
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
    public var localizedDescription: String? { nil }
        
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
    public var localizedDescription: String? { nil }
}

extension ALTAppPrivacyPermission: ALTAppPermission
{
    public var type: ALTAppPermissionType { .privacy }
    
    public var localizedName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .camera: return NSLocalizedString("Camera", comment: "")
        case .faceID: return NSLocalizedString("Face ID", comment: "")
        case .appleMusic: return NSLocalizedString("Apple Music", comment: "")
        case .localNetwork: return NSLocalizedString("Local Network", comment: "")
        case .bluetooth: return NSLocalizedString("Bluetooth (Always)", comment: "")
        case .calendars: return NSLocalizedString("Calendars", comment: "")
        case .microphone: return NSLocalizedString("Microphone", comment: "")
        default: return nil
        }
    }
    
    public var localizedDescription: String? { nil }
        
    public var symbolName: String? {
        switch self
        {
        case .photos: return "photo"
        case .camera: return "camera"
        case .faceID: return "faceid"
        case .appleMusic: return "music.note"
        case .localNetwork: return "wifi"
        case .bluetooth: return "dot.radiowaves.forward"
        case .calendars: return "calendar"
        case .microphone: return "mic"
        default: return nil
        }
    }
}

extension ALTAppBackgroundMode: ALTAppPermission
{
    public var type: ALTAppPermissionType { .backgroundMode }
    public var symbolName: String? { nil }
    
    public var localizedName: String? { nil }
    public var localizedDescription: String? { nil }
}
