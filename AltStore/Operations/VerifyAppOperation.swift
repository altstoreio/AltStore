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

@objc(VerifyAppOperation)
class VerifyAppOperation: ResultOperation<Void>
{
    let context: InstallAppOperationContext
    var verificationHandler: ((VerificationError) -> Bool)?
    
    init(context: InstallAppOperationContext)
    {
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
                    guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }
                    
                    try await self.verifyHash(of: app, at: ipaURL, matches: appVersion)
                    try await self.verifyDownloadedVersion(of: app, matches: appVersion)
                    
                    if let storeApp = await self.context.$appVersion.app
                    {
                        try await self.verifyPermissions(of: app, match: storeApp)
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

        print("[ALTLog] Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")

        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: app) }
    }
    
    func verifyDownloadedVersion(of app: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        let version = await $appVersion.version
        
        guard version == app.version else { throw VerificationError.mismatchedVersion(app.version, expectedVersion: version, app: app) }
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
        
        
        // Background Modes
        // App extensions can't have background modes, so don't need to worry about them.
        let allBackgroundModes: Set<ALTAppBackgroundMode>
        if let backgroundModes = app.bundle.infoDictionary?[Bundle.Info.backgroundModes] as? [String]
        {
            let backgroundModes = backgroundModes.lazy.map { ALTAppBackgroundMode($0) }
            allBackgroundModes = Set(backgroundModes)
        }
        else
        {
            allBackgroundModes = []
        }
        
        
        // Privacy
        let allPrivacyPermissions: Set<ALTAppPrivacyPermission>
        if #available(iOS 16, *)
        {
            let regex = Regex {
                "NS"
                
                // Capture permission "name"
                Capture {
                    OneOrMore(.anyGraphemeCluster)
                }
                
                "UsageDescription"
                
                // Optional suffix
                Optionally(OneOrMore(.anyGraphemeCluster))
            }
            
            let privacyPermissions = ([app] + app.appExtensions).flatMap { (app) in
                let permissions = app.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                    guard let match = key.wholeMatch(of: regex) else { return nil }
                    
                    let permission = ALTAppPrivacyPermission(rawValue: String(match.1))
                    return permission
                } ?? []
                 
                return permissions
            }
            
            allPrivacyPermissions = Set(privacyPermissions)
        }
        else
        {
            allPrivacyPermissions = []
        }
        
        
        // Verify permissions.
        let sourcePermissions: Set<AnyHashable> = Set(await $storeApp.perform { $0.permissions.map { AnyHashable($0.permission) } })
        let localPermissions: [any ALTAppPermission] = Array(allEntitlements) + Array(allBackgroundModes) + Array(allPrivacyPermissions)
        
        // To pass: EVERY permission in localPermissions must also appear in sourcePermissions.
        // If there is a single missing permission, throw error.
        let missingPermissions: [any ALTAppPermission] = localPermissions.filter { !sourcePermissions.contains(AnyHashable($0)) }
        guard missingPermissions.isEmpty else { throw VerificationError.undeclaredPermissions(missingPermissions, app: app) }
        
        return localPermissions
    }
}
