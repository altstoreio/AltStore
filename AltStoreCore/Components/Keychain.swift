//
//  Keychain.swift
//  AltStore
//
//  Created by Riley Testut on 6/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import KeychainAccess

import AltSign

import MarketplaceKit

@propertyWrapper
public struct KeychainItem<Value>
{
    public let key: String
    
    public var wrappedValue: Value? {
        get {
            switch Value.self
            {
            case is Data.Type: return try? Keychain.shared.keychain.getData(self.key) as? Value
            case is String.Type: return try? Keychain.shared.keychain.getString(self.key) as? Value
            default: return nil
            }
        }
        set {
            switch Value.self
            {
            case is Data.Type: Keychain.shared.keychain[data: self.key] = newValue as? Data
            case is String.Type: Keychain.shared.keychain[self.key] = newValue as? String
            default: break
            }
        }
    }
    
    public init(key: String)
    {
        self.key = key
    }
}

public class Keychain
{
    public static let shared = Keychain()
    
    #if MARKETPLACE
    //TODO: Change to match new bundle ID
    fileprivate let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore").accessibility(.afterFirstUnlock).synchronizable(true)
    #else
    fileprivate let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore").accessibility(.afterFirstUnlock).synchronizable(true)
    #endif
    
    @KeychainItem(key: "appleIDEmailAddress")
    public var appleIDEmailAddress: String?
    
    @KeychainItem(key: "appleIDPassword")
    public var appleIDPassword: String?
    
    @KeychainItem(key: "signingCertificatePrivateKey")
    public var signingCertificatePrivateKey: Data?
    
    @KeychainItem(key: "signingCertificateSerialNumber")
    public var signingCertificateSerialNumber: String?
    
    @KeychainItem(key: "signingCertificate")
    public var signingCertificate: Data?
    
    @KeychainItem(key: "signingCertificatePassword")
    public var signingCertificatePassword: String?
    
    @KeychainItem(key: "patreonAccessToken")
    public var patreonAccessToken: String?
    
    @KeychainItem(key: "patreonRefreshToken")
    public var patreonRefreshToken: String?
    
    @KeychainItem(key: "patreonCreatorAccessToken")
    public var patreonCreatorAccessToken: String?
    
    @KeychainItem(key: "patreonAccountID")
    public var patreonAccountID: String?
    
    private init()
    {
    }
    
    public func reset()
    {
        self.appleIDEmailAddress = nil
        self.appleIDPassword = nil
        self.signingCertificatePrivateKey = nil
        self.signingCertificateSerialNumber = nil
    }
}

// MarketplaceExtension communication
public extension Keychain
{
    func pendingInstall(for marketplaceID: AppleItemID) throws -> PendingAppInstall?
    {
        let key = self.pendingInstallKey(forMarketplaceID: marketplaceID)
        guard let data = try Keychain.shared.keychain.getData(key) else { return nil }
        
        let pendingInstall = try JSONDecoder().decode(PendingAppInstall.self, from: data)
        return pendingInstall
    }
    
    func setPendingInstall(for version: AppVersion, installVerificationToken: String) throws
    {
        guard let storeApp = version.storeApp,
              let marketplaceID = storeApp.marketplaceID,
              let buildVersion = version.buildVersion
        else { throw CocoaError(CocoaError.Code.coderInvalidValue) } //TODO: Replace with final error
        
        let pendingInstall = PendingAppInstall(appleItemID: marketplaceID, adpURL: version.downloadURL, version: version.version, buildVersion: buildVersion, installVerificationToken: installVerificationToken)
        
        let data = try JSONEncoder().encode(pendingInstall)
        let key = self.pendingInstallKey(forMarketplaceID: marketplaceID)
        Keychain.shared.keychain[data: key] = data
    }
    
    func removePendingInstall(for marketplaceID: AppleItemID) throws
    {
        let key = self.pendingInstallKey(forMarketplaceID: marketplaceID)
        try Keychain.shared.keychain.remove(key)
    }
}

private extension Keychain
{
    func pendingInstallKey(forMarketplaceID marketplaceID: AppleItemID) -> String
    {
        return "ALTPendingInstall_" + String(marketplaceID)
    }
}
