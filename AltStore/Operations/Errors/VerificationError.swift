//
//  VerificationError.swift
//  AltStore
//
//  Created by Riley Testut on 5/11/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltStoreCore
import AltSign

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = VerificationError
        
        // Legacy
        // case privateEntitlements = 0
        
        case mismatchedBundleIdentifiers = 1
        case iOSVersionNotSupported = 2
        
        case mismatchedHash = 3
        case mismatchedVersion = 4
        case mismatchedBuildVersion = 5
        
        case undeclaredPermissions = 6
        case addedPermissions = 7
    }
    
    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError {
        VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID)
    }
    
    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app, deviceOSVersion: osVersion, requiredOSVersion: requiredOSVersion)
    }
    
    static func mismatchedHash(_ hash: String, expectedHash: String, app: AppProtocol) -> VerificationError {
        VerificationError(code: .mismatchedHash, app: app, hash: hash, expectedHash: expectedHash)
    }
    
    static func mismatchedVersion(_ version: String, expectedVersion: String, app: AppProtocol) -> VerificationError {
        VerificationError(code: .mismatchedVersion, app: app, version: version, expectedVersion: expectedVersion)
    }
    
    static func mismatchedBuildVersion(_ version: String, expectedVersion: String, app: AppProtocol) -> VerificationError {
        VerificationError(code: .mismatchedBuildVersion, app: app, version: version, expectedVersion: expectedVersion)
    }
    
    static func undeclaredPermissions(_ permissions: [any ALTAppPermission], app: AppProtocol) -> VerificationError {
        VerificationError(code: .undeclaredPermissions, app: app, permissions: permissions)
    }
    
    static func addedPermissions(_ permissions: [any ALTAppPermission], appVersion: AppVersion) -> VerificationError {
        VerificationError(code: .addedPermissions, app: appVersion, permissions: permissions)
    }
}

struct VerificationError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var app: AppProtocol?
    var sourceBundleID: String?
    var deviceOSVersion: OperatingSystemVersion?
    var requiredOSVersion: OperatingSystemVersion?
    
    @UserInfoValue var hash: String?
    @UserInfoValue var expectedHash: String?
    
    @UserInfoValue var version: String?
    @UserInfoValue var expectedVersion: String?
    
    @UserInfoValue
    var permissions: [any ALTAppPermission]?
    
    var errorDescription: String? {
        //TODO: Make this automatic somehow with ALTLocalizedError
        guard self.errorFailure == nil else { return nil }
        
        switch self.code
        {
        case .iOSVersionNotSupported:
            guard let deviceOSVersion else { break }
            
            var failureReason = self.errorFailureReason
            if self.app == nil
            {
                // failureReason does not start with app name, so make first letter lowercase.
                let firstLetter = failureReason.prefix(1).lowercased()
                failureReason = firstLetter + failureReason.dropFirst()
            }
            
            let localizedDescription = String(format: NSLocalizedString("This device is running iOS %@, but %@", comment: ""), deviceOSVersion.stringValue, failureReason)
            return localizedDescription
            
        default: break
        }
        
        return self.errorFailureReason
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .mismatchedBundleIdentifiers:
            if let appBundleID = self.$app.bundleIdentifier, let bundleID = self.sourceBundleID
            {
                return String(format: NSLocalizedString("The bundle ID “%@” does not match the one specified by the source (“%@”).", comment: ""), appBundleID, bundleID)
            }
            else
            {
                return NSLocalizedString("The bundle ID does not match the one specified by the source.", comment: "")
            }
            
        case .iOSVersionNotSupported:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            let deviceOSVersion = self.deviceOSVersion ?? ProcessInfo.processInfo.operatingSystemVersion
            
            guard let requiredOSVersion else {
                return String(format: NSLocalizedString("%@ does not support iOS %@.", comment: ""), appName, deviceOSVersion.stringValue)
            }
            
            if deviceOSVersion > requiredOSVersion
            {
                // Device OS version is higher than maximum supported OS version.
                
                let failureReason = String(format: NSLocalizedString("%@ requires iOS %@ or earlier.", comment: ""), appName, requiredOSVersion.stringValue)
                return failureReason
            }
            else
            {
                // Device OS version is lower than minimum supported OS version.
                
                let failureReason = String(format: NSLocalizedString("%@ requires iOS %@ or later.", comment: ""), appName, requiredOSVersion.stringValue)
                return failureReason
            }
            
        case .mismatchedHash:
            let appName = self.$app.name ?? NSLocalizedString("the downloaded app", comment: "")
            return String(format: NSLocalizedString("The SHA-256 hash of %@ does not match the hash specified by the source.", comment: ""), appName)
            
        case .mismatchedVersion:
            let appName = self.$app.name ?? NSLocalizedString("the app", comment: "")
            return String(format: NSLocalizedString("The downloaded version of %@ does not match the version specified by the source.", comment: ""), appName)
            
        case .mismatchedBuildVersion:
            let appName = self.$app.name ?? NSLocalizedString("the app", comment: "")
            return String(format: NSLocalizedString("The downloaded version of %@ does not match the build number specified by the source.", comment: ""), appName)
            
        case .undeclaredPermissions:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ requires additional permissions not specified by the source.", comment: ""), appName)
            
        case .addedPermissions:
            let appName: String
            let installedVersion: String?

            if let appVersion = self.app as? AppVersion
            {
                let (name, version, previousVersion) = self.$app.perform { _ in (appVersion.name, appVersion.localizedVersion, appVersion.app?.installedApp?.localizedVersion) }
                
                appName = name + " \(version)"
                installedVersion = previousVersion.map { "(\(name) \($0))" } // Include app name because it looks weird to include build # in double parentheses without it.
            }
            else
            {
                appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
                installedVersion = nil
            }
            
            let baseMessage = String(format: NSLocalizedString("%@ requires more permissions than the version that is already installed", comment: ""), appName)
            
            let failureReason = [baseMessage, installedVersion].compactMap { $0 }.joined(separator: " ") + "."
            return failureReason
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .undeclaredPermissions:
            guard let permissionsDescription else { return nil }
            
            let baseMessage = NSLocalizedString("These permissions must be declared by the source in order for AltStore to install this app:", comment: "")
            let recoverySuggestion = [baseMessage, permissionsDescription].joined(separator: "\n\n")
            return recoverySuggestion
            
        case .addedPermissions:
            let recoverySuggestion = self.permissionsDescription
            return recoverySuggestion
            
        default: return nil
        }
    }
}

private extension VerificationError
{
    var permissionsDescription: String? {
        guard let permissions, !permissions.isEmpty else { return nil }
        
        let permissionsByType = Dictionary(grouping: permissions) { $0.type }
        let permissionSections = [ALTAppPermissionType.entitlement, .privacy, .backgroundMode].compactMap { (type) -> String? in
            guard let permissions = permissionsByType[type] else { return nil }
            
            // "Privacy:"
            var sectionText = "\(type.localizedName ?? type.rawValue):\n"
            
            // Sort permissions + join into single string.
            let sortedList = permissions.map { permission -> String in
                if let localizedName = permission.localizedName
                {
                    // "Entitlement Name (com.apple.entitlement.name)"
                    return "\(localizedName) (\(permission.rawValue))"
                }
                else
                {
                    // "com.apple.entitlement.name"
                    return permission.rawValue
                }
            }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending } // Case-insensitive sorting
                .joined(separator: "\n")
            
            sectionText += sortedList
            return sectionText
        }
        
        let permissionsDescription = permissionSections.joined(separator: "\n\n")
        return permissionsDescription
    }
}
