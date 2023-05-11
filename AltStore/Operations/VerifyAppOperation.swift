//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit

import AltStoreCore
import AltSign
import Roxas

import RegexBuilder

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = VerificationError
        
        case privateEntitlements
        case mismatchedBundleIdentifiers
        case iOSVersionNotSupported
        
        case mismatchedHash
        case mismatchedVersion
        case mismatchedBuildVersion
        
        case undeclaredPermissions
        case addedPermissions
    }
    
    static func privateEntitlements(_ entitlements: [String: Any], app: ALTApplication) -> VerificationError { VerificationError(code: .privateEntitlements, app: app, entitlements: entitlements) }
    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError  { VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID) }
    
    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app, deviceOSVersion: osVersion, requiredOSVersion: requiredOSVersion)
    }
    
    static func mismatchedHash(app: AppProtocol, hash: String, expectedHash: String) -> VerificationError {
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
    
    static func addedPermissions(_ permissions: [any ALTAppPermission], app: AppProtocol) -> VerificationError {
        VerificationError(code: .addedPermissions, app: app, permissions: permissions)
    }
}

private extension ALTEntitlement
{
    static var ignoredEntitlements: Set<ALTEntitlement> = [
        .applicationIdentifier,
        .teamIdentifier
    ]
}

struct VerificationError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var app: AppProtocol?
    var entitlements: [String: Any]?
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
        case .privateEntitlements:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ requires private permissions.", comment: ""), appName)
            
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
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ requires more permissions than the version that is already installed.", comment: ""), appName)
            
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .undeclaredPermissions:
            guard let permissions, !permissions.isEmpty else { return nil }
            
            let baseMessage = NSLocalizedString("These permissions must be declared by the source in order for AltStore to install this app:", comment: "")
            
            let permissionsByType = Dictionary(grouping: permissions) { $0.type }.mapValues { permissions in
                let permissions = permissions.lazy.map { permission in
                    if let localizedName = permission.localizedName
                    {
                        return "\(localizedName) (\(permission.rawValue))"
                    }
                    else
                    {
                        return permission.rawValue
                    }
                }.sorted()
                
                return permissions
            }
            
            var permissionsText = ""
            
            if let entitlements = permissionsByType[.entitlement]
            {
                permissionsText += NSLocalizedString("Entitlements", comment: "") + ":"
                permissionsText += "\n"
                permissionsText += entitlements.joined(separator: "\n")
                permissionsText += "\n\n"
            }
            
            if let entitlements = permissionsByType[.privacy]
            {
                permissionsText += NSLocalizedString("Privacy", comment: "") + ":"
                permissionsText += "\n"
                permissionsText += entitlements.joined(separator: "\n")
                permissionsText += "\n\n"
            }
            
            if let entitlements = permissionsByType[.backgroundMode]
            {
                permissionsText += NSLocalizedString("Background Modes", comment: "") + ":"
                permissionsText += "\n"
                permissionsText += entitlements.joined(separator: "\n")
                permissionsText += "\n\n"
            }
            
            let recoverySuggestion = baseMessage + "\n\n" + permissionsText
            return recoverySuggestion
            
        default: return nil
        }
    }
}

extension VerifyAppOperation
{
    enum PermissionsMode
    {
        case none
        case all
        case added
    }
}

@objc(VerifyAppOperation)
class VerifyAppOperation: ResultOperation<Void>
{
    let context: InstallAppOperationContext
    var verificationHandler: ((VerificationError) -> Bool)?
    
    var permissionsMode: PermissionsMode = .none
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
                
        Task<Void, Never> { () -> Void in
            do
            {
                if let error = self.context.error
                {
                    throw error
                }

                let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
                self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)

                guard let app = self.context.app else { throw OperationError.invalidParameters }

                guard app.bundleIdentifier == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
                }

                guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                    throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
                }

                // Check context.appVersion FIRST, then fall back to context.storeApp if nil.
                // Otherwise, when downloading an old version we may accidentally compare the wrong hash.
                // NVM
                if let expectedHash = self.context.$appVersion.sha256
                {
                    guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }

                    let data = try Data(contentsOf: ipaURL)
                    let sha256Hash = SHA256.hash(data: data)
                    let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()

                    print("[ALTLog] Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")

                    guard hashString == expectedHash else { throw VerificationError.mismatchedHash(app: app, hash: hashString, expectedHash: expectedHash) }
                }
                
                if let version = self.context.$appVersion.version
                {
                    guard version == app.version else { throw VerificationError.mismatchedVersion(app.version, expectedVersion: version, app: app) }
                }
                
                if let buildVersion = self.context.$appVersion.buildVersion
                {
                    guard buildVersion == app.buildVersion else { throw VerificationError.mismatchedBuildVersion(app.buildVersion, expectedVersion: buildVersion, app: app) }
                }

                do
                {
                    try await self.verifyPermissions(for: app)
                }
                catch let error as VerificationError
                {
                    try await self.process(error)
                }

                if #available(iOS 13.5, *)
                {
                    // No psychic paper, so we can ignore private entitlements
                    app.hasPrivateEntitlements = false
                }
                else
                {
                    // Make sure this goes last, since once user responds to alert we don't do any more app verification.
                    if let commentStart = app.entitlementsString.range(of: "<!---><!-->"), let commentEnd = app.entitlementsString.range(of: "<!-- -->")
                    {
                        // Psychic Paper private entitlements.

                        let entitlementsStart = app.entitlementsString.index(after: commentStart.upperBound)
                        let rawEntitlements = String(app.entitlementsString[entitlementsStart ..< commentEnd.lowerBound])

                        let plistTemplate = """
                            <?xml version="1.0" encoding="UTF-8"?>
                            <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                            <plist version="1.0">
                                <dict>
                                %@
                                </dict>
                            </plist>
                            """
                        let entitlementsPlist = String(format: plistTemplate, rawEntitlements)
                        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsPlist.data(using: .utf8)!, options: [], format: nil) as! [String: Any]

                        app.hasPrivateEntitlements = true
                        let error = VerificationError.privateEntitlements(entitlements, app: app)
                        try await self.process(error)
                    }
                    else
                    {
                        app.hasPrivateEntitlements = false
                    }
                }
                
                self.finish(.success(()))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}

private extension VerifyAppOperation
{
    @MainActor
    func process(_ error: VerificationError) async throws
    {
        guard let presentingViewController = self.context.presentingViewController else { throw error }
        
        switch error.code
        {
        case .privateEntitlements:
            guard let entitlements = error.entitlements else { throw error }
            let permissions = entitlements.keys.sorted().joined(separator: "\n")
            let message = String(format: NSLocalizedString("""
                You must allow access to these private permissions before continuing:
                
                %@
                
                Private permissions allow apps to do more than normally allowed by iOS, including potentially accessing sensitive private data. Make sure to only install apps from sources you trust.
                """, comment: ""), permissions)
            
            do
            {
                try await presentingViewController.presentConfirmationAlert(title: error.failureReason ?? error.localizedDescription,
                                                                  message: message,
                                                                  primaryAction: UIAlertAction(title: NSLocalizedString("Allow Access", comment: ""), style: .destructive),
                                                                  cancelAction: UIAlertAction(title: NSLocalizedString("Deny Access", comment: ""), style: .default))
            }
            catch is CancellationError
            {
                throw error
            }
            
        case .addedPermissions:
            guard let entitlements = error.permissions, let app = self.context.app else { throw error }

            try await withCheckedThrowingContinuation { continuation in
                let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: entitlements, mode: .added)
                reviewPermissionsViewController.title = NSLocalizedString("Review Permissions", comment: "")
                reviewPermissionsViewController.resultHandler = { (didAccept) in
                    if didAccept
                    {
                        continuation.resume()
                    }
                    else
                    {
                        continuation.resume(throwing: CancellationError())
                    }
                }
                
                let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
                presentingViewController.present(navigationController, animated: true)
            }
            
        case .mismatchedBundleIdentifiers, .iOSVersionNotSupported, .mismatchedHash, .mismatchedVersion, .mismatchedBuildVersion, .undeclaredPermissions: throw error
        }
    }
    
    func verifyPermissions(for app: ALTApplication) async throws
    {
        switch self.permissionsMode
        {
        case .none: break
        case .added:
            // Verify source permissions match.
            let allPermissions = try self.verifyPermissionsMatchSource(for: app)
            
            let installedAppURL = InstalledApp.fileURL(for: app)
            guard let installedApp = ALTApplication(fileURL: installedAppURL), self.context.$appVersion.storeApp?.installedApp != nil else {
                //TODO: Do we actually want to throw error?
                throw OperationError.invalidParameters
            }
            
            var previousEntitlements = Set(installedApp.entitlements.keys)
            for appExtension in app.appExtensions
            {
                previousEntitlements.formUnion(appExtension.entitlements.keys)
            }
            
            let addedEntitlements = Array(allPermissions.lazy.compactMap { $0 as? ALTEntitlement }.filter { !previousEntitlements.contains($0) })
            
            guard addedEntitlements.isEmpty else {
                throw VerificationError.addedPermissions(addedEntitlements, app: app)
            }
            
        case .all:
            guard let presentingViewController = self.context.presentingViewController else { return }
            
            // Verify source permissions match.
            let allPermissions = try self.verifyPermissionsMatchSource(for: app)
            let entitlements = allPermissions.compactMap { $0 as? ALTEntitlement }
            
            @MainActor
            func verify() async throws
            {
                try await withCheckedThrowingContinuation { continuation in
                    let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: entitlements, mode: .all)
                    reviewPermissionsViewController.title = NSLocalizedString("Review Permissions", comment: "")
                    reviewPermissionsViewController.resultHandler = { (didAccept) in
                        if didAccept
                        {
                            continuation.resume()
                        }
                        else
                        {
                            continuation.resume(throwing: CancellationError())
                        }
                    }
                    
                    let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
                    presentingViewController.present(navigationController, animated: true)
                }
            }
            
            try await verify()
        }
    }
    
    @discardableResult
    func verifyPermissionsMatchSource(for app: ALTApplication) throws -> [any ALTAppPermission]
    {
        var allEntitlements = Set(app.entitlements.keys)
        for appExtension in app.appExtensions
        {
            allEntitlements.formUnion(appExtension.entitlements.keys)
        }
             
        // Don't include any ignored entitlements.
        allEntitlements = allEntitlements.filter { !ALTEntitlement.ignoredEntitlements.contains($0) }
        
        // nil storeApp == sideloading from Files.
        guard let storeApp = self.context.$appVersion.storeApp else { return Array(allEntitlements) }
        
        // App extensions can't have background modes, so don't need to worry about them.
        var allBackgroundModes = Set<ALTAppBackgroundMode>()
        if let backgroundModes = app.bundle.infoDictionary?[Bundle.Info.backgroundModes] as? [String]
        {
            let backgroundModes = backgroundModes.map { ALTAppBackgroundMode($0) }
            allBackgroundModes.formUnion(backgroundModes)
        }
        
        var allPrivacyPermissions = Set<ALTAppPrivacyPermission>()
        
        if #available(iOS 16, *)
        {
            let regex = Regex {
                "NS"
                
                Capture {
                    OneOrMore(.anyGraphemeCluster)
                }
                
                "UsageDescription"
                
                // Optional suffix
                Optionally(OneOrMore(.anyGraphemeCluster))
            }
            
            let privacyPermissions = app.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                guard let match = key.wholeMatch(of: regex) else { return nil }
                
                let permission = ALTAppPrivacyPermission(rawValue: String(match.1))
                return permission
            } ?? []
            allPrivacyPermissions.formUnion(privacyPermissions)
            
            for appExtension in app.appExtensions
            {
                let privacyPermissions = appExtension.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                    guard let match = key.wholeMatch(of: regex) else { return nil }
                    
                    let permission = ALTAppPrivacyPermission(rawValue: String(match.1))
                    return permission
                } ?? []
                allPrivacyPermissions.formUnion(privacyPermissions)
            }
        }
        
        let rawSourcePermissions = self.context.$appVersion.get { _ in storeApp.permissions.map { $0.permission } }
        let sourcePermissions = Set(rawSourcePermissions.map { AnyHashable($0) })
        
        let allPermissions: [any ALTAppPermission] = Array(allEntitlements) + Array(allBackgroundModes) + Array(allPrivacyPermissions)
        
        var missingPermissions: [any ALTAppPermission] = []
        
        // To pass: EVERY permission in allPermissions must also appear in storeAppPermissions.
        for permission in allPermissions // where !storeAppPermissions.contains(AnyHashable(permission)) BUG: Cannot compile :(
        {
            //TODO: Case-sensitive?
            guard !sourcePermissions.contains(AnyHashable(permission)) else { continue }
            
//            if let entitlement = permission as? ALTEntitlement
//            {
//                guard !ALTEntitlement.ignoredEntitlements.contains(entitlement) else { continue }
//            }
            
            missingPermissions.append(permission)
        }
        
        // If there is a single missing permission, throw error.
        guard missingPermissions.isEmpty else {
            throw VerificationError.undeclaredPermissions(missingPermissions, app: app)
        }
        
        return allPermissions
    }
}
