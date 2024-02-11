//
//  ALTAppPermission.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import RegexBuilder

import AltSign

extension ALTAppPermissionType
{
    public var localizedName: String? {
        switch self
        {
        case .unknown: return NSLocalizedString("Permission", comment: "")
        case .entitlement: return NSLocalizedString("Entitlement", comment: "")
        case .privacy: return NSLocalizedString("Privacy Permission", comment: "")
        default: return nil
        }
    }
    
    fileprivate var knownPermissionsKey: String? {
        switch self
        {
        case .unknown: return nil
        case .entitlement: return "entitlements"
        case .privacy: return "privacy"
        default: return nil
        }
    }
}

public protocol ALTAppPermission: RawRepresentable<String>, Hashable
{
    var type: ALTAppPermissionType { get }
    var synthesizedName: String? { get } // Kupo!
    
    // Default implementations
    var localizedName: String? { get }
    var localizedDescription: String? { get }
    var symbolName: String? { get }
    
    // Convenience properties (also with default implementations).
    // Would normally just be in extension, except that crashes Swift 5.8 compiler ¯\_(ツ)_/¯
    var isKnown: Bool { get }
    var effectiveSymbolName: String { get }
    var localizedDisplayName: String { get }
}

private struct KnownPermission: Decodable
{
    var localizedName: String
    var localizedDescription: String?
    var rawValue: String
    var symbolName: String
    
    private enum CodingKeys: String, CodingKey
    {
        case localizedName = "name"
        case localizedDescription = "description"
        case rawValue = "key"
        case symbolName = "symbol"
    }
}

private let knownPermissions: [String: [String: KnownPermission]] = {
    guard let fileURL = Bundle(for: DatabaseManager.self).url(forResource: "Permissions", withExtension: "plist"),
          let data = try? Data(contentsOf: fileURL),
          let propertyList = try? PropertyListDecoder().decode([String: [String: KnownPermission]].self, from: data)
    else {
        fatalError("Could not decode Permissions.plist.")
    }
    
    return propertyList
}()

public extension ALTAppPermission
{
    private var knownPermission: KnownPermission? {
        guard let key = self.type.knownPermissionsKey,
              let permissions = knownPermissions[key]
        else { return nil }
        
        let knownPermission = permissions[self.rawValue]
        return knownPermission
    }
    
    var localizedName: String? { self.knownPermission?.localizedName }
    var localizedDescription: String? { self.knownPermission?.localizedDescription }
    var symbolName: String? { self.knownPermission?.symbolName }
}

public extension ALTAppPermission
{
    var isKnown: Bool {
        // Assume all known permissions have non-nil localizedNames.
        return self.localizedName != nil
    }
    
    var effectiveSymbolName: String { self.symbolName ?? "lock" }
    
    var localizedDisplayName: String {
        return self.localizedName ?? self.synthesizedName ?? self.rawValue
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
    public var synthesizedName: String? { nil }
    
    public var rawValue: String
    
    public init(rawValue: String)
    {
        self.rawValue = rawValue
    }
}

extension ALTEntitlement: ALTAppPermission
{
    public var type: ALTAppPermissionType { .entitlement }
    
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
}

extension ALTAppPrivacyPermission: ALTAppPermission
{
    public var type: ALTAppPermissionType { .privacy }
    
    public var synthesizedName: String? {
        guard #available(iOS 16, *), let match = self.rawValue.wholeMatch(of: Regex.privacyPermission) else { return nil }
        
        let synthesizedNamed = String(match.1)
        return synthesizedNamed
    }
}
