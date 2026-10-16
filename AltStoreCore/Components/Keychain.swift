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

@propertyWrapper
public struct KeychainItem<Value>
{
    public let key: String
    public let synchronizable: Bool
    
    public var wrappedValue: Value? {
        get {
            let keychain = self.synchronizable ? Keychain.shared.keychain : Keychain.shared.localKeychain
            switch Value.self
            {
            case is Data.Type: return try? keychain.getData(self.key) as? Value
            case is String.Type: return try? keychain.getString(self.key) as? Value
            default: return nil
            }
        }
        set {
            let keychain = self.synchronizable ? Keychain.shared.keychain : Keychain.shared.localKeychain
            switch Value.self
            {
            case is Data.Type: keychain[data: self.key] = newValue as? Data
            case is String.Type: keychain[self.key] = newValue as? String
            default: break
            }
        }
    }
    
    public init(key: String, synchronizable: Bool = true)
    {
        self.key = key
        self.synchronizable = synchronizable
    }
}

public class Keychain
{
    public static let shared = Keychain()
    
    fileprivate let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore").accessibility(.afterFirstUnlock).synchronizable(true)
    fileprivate let localKeychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore.Local").accessibility(.afterFirstUnlock).synchronizable(false)
    
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
    
    @KeychainItem(key: "anisetteIdentityKey", synchronizable: false)
    public var anisetteIdentityKey: Data?

    @KeychainItem(key: "anisetteADIPB", synchronizable: false)
    public var anisetteADIPB: Data?

    @KeychainItem(key: "anisetteProvisioningClientInfo", synchronizable: false)
    public var anisetteProvisioningClientInfo: String?

    @KeychainItem(key: "devicePairingFile", synchronizable: false)
    public var devicePairingFile: Data?

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
