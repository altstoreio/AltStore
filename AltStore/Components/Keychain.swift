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
struct KeychainItem<Value>
{
    let key: String
    
    var wrappedValue: Value? {
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
    
    init(key: String)
    {
        self.key = key
    }
}

class Keychain
{
    static let shared = Keychain()
    
    fileprivate let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore").accessibility(.afterFirstUnlock).synchronizable(true)
    
    @KeychainItem(key: "appleIDEmailAddress")
    var appleIDEmailAddress: String?
    
    @KeychainItem(key: "appleIDPassword")
    var appleIDPassword: String?
    
    @KeychainItem(key: "signingCertificatePrivateKey")
    var signingCertificatePrivateKey: Data?
    
    @KeychainItem(key: "signingCertificateSerialNumber")
    var signingCertificateSerialNumber: String?
    
    @KeychainItem(key: "signingCertificate")
    var signingCertificate: Data?
    
    @KeychainItem(key: "signingCertificatePassword")
    var signingCertificatePassword: String?
    
    @KeychainItem(key: "patreonAccessToken")
    var patreonAccessToken: String?
    
    @KeychainItem(key: "patreonRefreshToken")
    var patreonRefreshToken: String?
    
    @KeychainItem(key: "patreonCreatorAccessToken")
    var patreonCreatorAccessToken: String?
    
    private init()
    {
    }
    
    func reset()
    {
        self.appleIDEmailAddress = nil
        self.appleIDPassword = nil
        self.signingCertificatePrivateKey = nil
        self.signingCertificateSerialNumber = nil
    }
}
