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

private extension ALTEntitlement
{
    static var ignoredEntitlements: Set<ALTEntitlement> = [
        .applicationIdentifier,
        .teamIdentifier
    ]
}

extension VerifyAppOperation
{
    enum PermissionReviewMode
    {
        case none
        case all
        case added
    }
}

@objc(VerifyAppOperation)
class VerifyAppOperation: ResultOperation<Void>
{
    let permissionsMode: PermissionReviewMode
    let context: InstallAppOperationContext
    
    init(permissionsMode: PermissionReviewMode, context: InstallAppOperationContext)
    {
        self.permissionsMode = permissionsMode
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
            self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)
            
            guard let app = self.context.app else { throw OperationError.invalidParameters }
            
            Logger.sideload.notice("Verifying app \(self.context.bundleIdentifier, privacy: .public)...")
            
            guard app.bundleIdentifier == self.context.bundleIdentifier else {
                throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            guard let appVersion = self.context.appVersion else {
                return self.finish(.success(()))
            }
            
            Task<Void, Never>  {
                do
                {
                    do
                    {
                        guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }
                        
                        try await self.verifyHash(of: app, at: ipaURL, matches: appVersion)
                        try await self.verifyDownloadedVersion(of: app, matches: appVersion)
                        
                        // Verify permissions last in case user bypasses error.
                        try await self.verifyPermissions(of: app, match: appVersion)
                    }
                    catch let error as VerificationError where error.code == .undeclaredPermissions
                    {
                        #if !BETA
                        throw error
                        #endif
                        
                        if let recommendedSources = UserDefaults.shared.recommendedSources, let sourceID = await self.context.$appVersion.sourceID
                        {
                            let isRecommended = recommendedSources.contains { $0.identifier == sourceID }
                            guard !isRecommended else {
                                // Don't enforce permission checking for Recommended Sources while 2.0 is in beta.
                                return self.finish(.success(()))
                            }
                        }
                        
                        // While in beta, allow users to temporarily bypass permissions alert
                        // so source maintainers have time to update their sources.
                        guard let presentingViewController = self.context.presentingViewController else { throw error }
                        
                        let message = NSLocalizedString("While AltStore 2.0 is in beta, you may choose to ignore this warning at your own risk until the source is updated.", comment: "")
                        
                        let ignoreAction = await UIAlertAction(title: NSLocalizedString("Install Anyway", comment: ""), style: .destructive)
                        let viewPermissionsAction = await UIAlertAction(title: NSLocalizedString("View Permisions", comment: ""), style: .default)
                        
                        while true
                        {
                            let action = try await presentingViewController.presentConfirmationAlert(title: error.errorFailureReason,
                                                                                                     message: message,
                                                                                                     actions: [ignoreAction, viewPermissionsAction])
                            
                            guard action == viewPermissionsAction else { break } // break loop to continue with installation (unless we're viewing permissions).
                            
                            await presentingViewController.presentAlert(title: NSLocalizedString("Undeclared Permissions", comment: ""), message: error.recoverySuggestion)
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
        catch
        {
            self.finish(.failure(error))
        }
    }
}

private extension VerifyAppOperation
{
    func verifyHash(of app: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        // Do nothing if source doesn't provide hash.
        guard let expectedHash = await $appVersion.sha256 else { return }

        let data = try Data(contentsOf: ipaURL)
        let sha256Hash = SHA256.hash(data: data)
        let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()
        
        Logger.sideload.debug("Comparing app hash (\(hashString, privacy: .public)) against expected hash (\(expectedHash, privacy: .public))...")
        
        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: app) }
    }
    
    func verifyDownloadedVersion(of app: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        let (version, buildVersion) = await $appVersion.perform { ($0.version, $0.buildVersion) }
        
        guard version == app.version else { throw VerificationError.mismatchedVersion(app.version, expectedVersion: version, app: app) }
        
        if let buildVersion
        {
            guard buildVersion == app.buildVersion else { throw VerificationError.mismatchedBuildVersion(app.buildVersion, expectedVersion: buildVersion, app: app) }
        }
    }
    
    func verifyPermissions(of app: ALTApplication, @AsyncManaged match appVersion: AppVersion) async throws
    {
        guard self.permissionsMode != .none else { return }
        guard let storeApp = await $appVersion.app else { throw OperationError.invalidParameters }
        
        // Verify source permissions match first.
        _ = try await self.verifyPermissions(of: app, match: storeApp)
        
        // TODO: Uncomment to verify added permissions.
        // switch self.permissionsMode
        // {
        // case .none, .all: break
        // case .added:
        //     let installedAppURL = InstalledApp.fileURL(for: app)
        //     guard let previousApp = ALTApplication(fileURL: installedAppURL) else { throw OperationError.appNotFound(name: app.name) }
        //
        //     var previousEntitlements = Set(previousApp.entitlements.keys)
        //     for appExtension in previousApp.appExtensions
        //     {
        //         previousEntitlements.formUnion(appExtension.entitlements.keys)
        //     }
        //
        //     // Make sure all entitlements already exist in previousApp.
        //     let addedEntitlements = Array(allPermissions.lazy.compactMap { $0 as? ALTEntitlement }.filter { !previousEntitlements.contains($0) })
        //     guard addedEntitlements.isEmpty else { throw VerificationError.addedPermissions(addedEntitlements, appVersion: appVersion) }
        // }
    }
    
    @discardableResult
    func verifyPermissions(of app: ALTApplication, @AsyncManaged match storeApp: StoreApp) async throws -> [any ALTAppPermission]
    {
        // Entitlements
        var allEntitlements = Set(app.entitlements.keys)
        for appExtension in app.appExtensions
        {
            allEntitlements.formUnion(appExtension.entitlements.keys)
        }
             
        // Filter out ignored entitlements.
        allEntitlements = allEntitlements.filter { !ALTEntitlement.ignoredEntitlements.contains($0) }
        
        
        // Privacy
        let allPrivacyPermissions = ([app] + app.appExtensions).flatMap { (app) in
            let permissions = app.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                if #available(iOS 16, *)
                {
                    guard key.wholeMatch(of: Regex.privacyPermission) != nil else { return nil }
                }
                else
                {
                    guard key.contains("UsageDescription") else { return nil }
                }
                
                let permission = ALTAppPrivacyPermission(rawValue: key)
                return permission
            } ?? []
            
            return permissions
        }
        
        // Verify permissions.
        let sourcePermissions: Set<AnyHashable> = Set(await $storeApp.perform { $0.permissions.map { AnyHashable($0.permission) } })
        let localPermissions: [any ALTAppPermission] = Array(allEntitlements) + Array(allPrivacyPermissions)
        
        // To pass: EVERY permission in localPermissions must also appear in sourcePermissions.
        // If there is a single missing permission, throw error.
        let missingPermissions: [any ALTAppPermission] = localPermissions.filter { permission in
            if sourcePermissions.contains(AnyHashable(permission))
            {
                // `permission` exists in source, so return false.
                return false
            }
            else if permission.type == .privacy
            {
                guard #available(iOS 16, *) else {
                    // Assume all privacy permissions _are_ included in source on pre-iOS 16 devices.
                    return false
                }
                
                // Special-handling for legacy privacy permissions.
                if let match = permission.rawValue.firstMatch(of: Regex.privacyPermission),
                   case let legacyPermission = ALTAppPrivacyPermission(rawValue: String(match.1)),
                   sourcePermissions.contains(AnyHashable(legacyPermission))
                {
                    // The legacy name of this permission exists in the source, so return false.
                    return false
                }
            }
            
            // Source doesn't contain permission or its legacy name, so assume it is missing.
            return true
        }
        
        guard missingPermissions.isEmpty else {
            // There is at least one undeclared permission, so throw error.
            throw VerificationError.undeclaredPermissions(missingPermissions, app: app)
        }
        
        return localPermissions
    }
}
