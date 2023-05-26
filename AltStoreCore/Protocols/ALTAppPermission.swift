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
        default: return nil
        }
    }
}

public protocol ALTAppPermission: RawRepresentable<String>, Hashable
{
    var type: ALTAppPermissionType { get }
    var symbolName: String? { get }
    
    var localizedName: String? { get }
    var synthesizedName: String? { get } // Kupo!
    
    var localizedDescription: String? { get }
    
    // Convenience properties with default implementations.
    // Would normally just be in extension, except that crashes Swift 5.8 compiler ¯\_(ツ)_/¯
    var isKnown: Bool { get }
    var effectiveSymbolName: String { get }
    var localizedDisplayName: String { get }
}

public extension ALTAppPermission
{
    var isKnown: Bool {
        // Assume all known permissions have non-nil localizedDescriptions.
        return self.localizedDescription != nil
    }
    
    var effectiveSymbolName: String { self.symbolName ?? "lock" }
    
    var localizedDisplayName: String {
        return self.localizedName ?? self.synthesizedName ?? self.rawValue
    }
}

public extension ALTAppPermission
{
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
    public var synthesizedName: String? { nil }
    
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
    
    public var synthesizedName: String? {
        // Attempt to convert last component of entitlement to human-readable string.
        // e.g. com.apple.developer.kernel.increased-memory-limit -> "Increased Memory Limit"
        let components = self.rawValue.components(separatedBy: ".")
        guard let rawName = components.last else { return nil }
        
        let words = rawName.components(separatedBy: "-").map { word in
            switch word.lowercased()
            {
            case "carplay": return NSLocalizedString("CarPlay", comment: "")
            default: return word.localizedCapitalized
            }
        }
        
        let synthesizedName = words.joined(separator: " ")
        return synthesizedName
    }
    
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
    
    public var synthesizedName: String? { nil }
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
