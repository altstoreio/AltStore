//
//  SourceError.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

extension SourceError
{
    public enum Code: Int, ALTErrorCode
    {
        public typealias Error = SourceError
        
        case unsupported
        case duplicateBundleID
        case duplicateVersion
        
        case blocked
        case changedID
        case duplicateID
        
        case missingPermissionUsageDescription
        case unknownPermissionType
    }
    
    public static func unsupported(_ source: Source) -> SourceError { SourceError(code: .unsupported, source: source) }
    public static func duplicateBundleID(_ bundleID: String, source: Source) -> SourceError { SourceError(code: .duplicateBundleID, source: source, bundleID: bundleID) }
    public static func duplicateVersion(_ version: String, for app: StoreApp, source: Source) -> SourceError { SourceError(code: .duplicateVersion, source: source, app: app, version: version) }
    
    public static func blocked(_ source: Source) -> SourceError { SourceError(code: .blocked, source: source) }
    
    public static func changedID(_ identifier: String, previousID: String, for source: Source) -> SourceError { SourceError(code: .changedID, source: source, sourceID: identifier, previousSourceID: previousID) }
    public static func duplicateID(_ source: Source, existingSource: Source?) -> SourceError { SourceError(code: .duplicateID, source: source, existingSource: existingSource) }
    
    public static func missingPermissionUsageDescription(permission: String, type: ALTAppPermissionType, app: StoreApp, source: Source) -> SourceError {
        SourceError(code: .missingPermissionUsageDescription, source: source, app: app, permission: permission, permissionType: type)
    }
    
    public static func unknownPermissionType(app: StoreApp, source: Source) -> SourceError {
        SourceError(code: .unknownPermissionType, source: source, app: app)
    }
}

public struct SourceError: ALTLocalizedError
{
    public let code: Code
    public var errorTitle: String?
    public var errorFailure: String?
    
    @Managed
    public var source: Source
    
    @Managed
    public var app: StoreApp?
    
    public var bundleID: String?
    public var version: String?
    
    @UserInfoValue
    public var sourceID: String?
    
    @UserInfoValue
    public var previousSourceID: String?
    
    @Managed
    public var existingSource: Source?
    
    @UserInfoValue
    public var permission: String?
    
    @UserInfoValue
    public var permissionType: ALTAppPermissionType?
    
    public var errorFailureReason: String {
        switch self.code
        {
        case .unsupported: return String(format: NSLocalizedString("The source “%@” is not supported by this version of AltStore.", comment: ""), self.$source.name)
        case .duplicateBundleID:
            let bundleIDFragment = self.bundleID.map { String(format: NSLocalizedString("the bundle identifier %@", comment: ""), $0) } ?? NSLocalizedString("the same bundle identifier", comment: "")
            let failureReason = String(format: NSLocalizedString("The source “%@” contains multiple apps with %@.", comment: ""), self.$source.name, bundleIDFragment)
            return failureReason
            
        case .duplicateVersion:
            var versionFragment = NSLocalizedString("duplicate versions", comment: "")
            if let version
            {
                versionFragment += " (\(version))"
            }
            
            let appFragment: String
            if let name = self.$app.name, let bundleID = self.$app.bundleIdentifier
            {
                appFragment = name + " (\(bundleID))"
            }
            else
            {
                appFragment = NSLocalizedString("one or more apps", comment: "")
            }
                        
            let failureReason = String(format: NSLocalizedString("The source “%@” contains %@ for %@.", comment: ""), self.$source.name, versionFragment, appFragment)
            return failureReason
            
        case .blocked:
            let failureReason = String(format: NSLocalizedString("The source “%@” has been blocked by AltStore for security reasons.", comment: ""), self.$source.name)
            return failureReason
            
        case .changedID:
            let failureReason = String(format: NSLocalizedString("The identifier of the source “%@” has changed.", comment: ""), self.$source.name)
            return failureReason
            
        case .duplicateID:
            let sourceID = self.$source.identifier
            let baseMessage = String(format: NSLocalizedString("A source with the identifier '%@' already exists", comment: ""), sourceID)
            guard let name = self.$existingSource.name else { return baseMessage + "." }
            
            let failureReason = baseMessage + " (“\(name)”)."
            return failureReason
            
        case .missingPermissionUsageDescription:
            let appName = self.$app.name.map { "“\($0)”" } ?? String(format: NSLocalizedString("an app in source “%@”", comment: ""), self.$source.name)
            let permissionType = self.permissionType?.localizedName ?? NSLocalizedString("permission", comment: "")
            
            guard let permission else {
                return String(format: NSLocalizedString("%@ for %@ is missing a usage description.", comment: ""), permissionType, appName)
            }
            
            let failureReason = String(format: NSLocalizedString("The %@ “%@” for %@ is missing a usage description.", comment: ""), permissionType.lowercased(), permission, appName)
            return failureReason
            
        case .unknownPermissionType:
            let appName = self.$app.name.map { "“\($0)”" } ?? String(format: NSLocalizedString("an app in source “%@”", comment: ""), self.$source.name)
            let failureReason = String(format: NSLocalizedString("Unknown permission type for %@.", comment: ""), appName)
            return failureReason
        }
    }
    
    public var recoverySuggestion: String? {
        switch self.code
        {
        case .blocked: return NSLocalizedString("For your protection, please remove the source and uninstall all apps downloaded from it.", comment: "")
        case .changedID: return NSLocalizedString("A source cannot change its identifier once added. This source can no longer be updated.", comment: "")
        case .duplicateID:
//            let sourceName = self.$existingSource.name.map { String(format: NSLocalizedString("the source “%@”", comment: ""), $0) } ?? NSLocalizedString("the existing source", comment: "")
//
//            let failureReason = String(format: NSLocalizedString("Please remove %@ in order to add this one.", comment: ""), sourceName)
//            return failureReason
            
            let failureReason = NSLocalizedString("Please remove the existing source in order to add this one.", comment: "")
            return failureReason
            
        default: return nil
        }
    }
}
