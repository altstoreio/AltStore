//
//  SourceError.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltStoreCore

extension SourceError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = SourceError
        
        case unsupported
        case duplicateBundleID
        case duplicateVersion
        
        case blocked
        case changedID
        case duplicate
        
        case missingPermissionUsageDescription
    }
    
    static func unsupported(_ source: Source) -> SourceError { SourceError(code: .unsupported, source: source) }
    static func duplicateBundleID(_ bundleID: String, source: Source) -> SourceError { SourceError(code: .duplicateBundleID, source: source, bundleID: bundleID) }
    static func duplicateVersion(_ version: String, for app: StoreApp, source: Source) -> SourceError { SourceError(code: .duplicateVersion, source: source, app: app, version: version) }
    
    static func blocked(_ source: Source) -> SourceError { SourceError(code: .blocked, source: source) }
    static func changedID(_ identifier: String, previousID: String, source: Source) -> SourceError { SourceError(code: .changedID, source: source, sourceID: identifier, previousSourceID: previousID) }
    static func duplicate(_ source: Source, previousSourceName: String?) -> SourceError { SourceError(code: .duplicate, source: source, previousSourceName: previousSourceName) }
    
    static func missingPermissionUsageDescription(for permission: any ALTAppPermission, app: StoreApp, source: Source) -> SourceError {
        SourceError(code: .missingPermissionUsageDescription, source: source, app: app, permission: permission)
    }
}

struct SourceError: ALTLocalizedError
{
    let code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var source: Source
    @Managed var app: StoreApp?
    var bundleID: String?
    var version: String?
    
    @UserInfoValue var previousSourceName: String?
    
    // Store in userInfo so they can be viewed from Error Log.
    @UserInfoValue var sourceID: String?
    @UserInfoValue var previousSourceID: String?
    
    @UserInfoValue
    var permission: (any ALTAppPermission)?
    
    var errorFailureReason: String {
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
            
        case .duplicate:
            let baseMessage = String(format: NSLocalizedString("A source with the identifier '%@' already exists", comment: ""), self.$source.identifier)
            guard let previousSourceName else { return baseMessage + "." }
            
            let failureReason = baseMessage + " (“\(previousSourceName)”)."
            return failureReason
            
        case .missingPermissionUsageDescription:
            let appName = self.$app.name ?? String(format: NSLocalizedString("an app in source “%@”", comment: ""), self.$source.name)
            guard let permission else {
                return String(format: NSLocalizedString("A permission for %@ is missing a usage description.", comment: ""), appName)
            }
            
            let permissionType = permission.type.localizedName ?? NSLocalizedString("Permission", comment: "")
            let failureReason = String(format: NSLocalizedString("The %@ '%@' for %@ is missing a usage description.", comment: ""), permissionType.lowercased(), permission.rawValue, appName)
            return failureReason
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .blocked: return NSLocalizedString("For your protection, please remove the source and uninstall all apps downloaded from it.", comment: "")
        case .changedID: return NSLocalizedString("A source cannot change its identifier once added. This source can no longer be updated.", comment: "")
        case .duplicate:
            let failureReason = NSLocalizedString("Please remove the existing source in order to add this one.", comment: "")
            return failureReason
            
        default: return nil
        }
    }
}
