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

class Keychain
{
    static let shared = Keychain()
    
    private let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltStore").accessibility(.afterFirstUnlock).synchronizable(true)
    
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

extension Keychain
{
    var appleIDEmailAddress: String? {
        get {
            let emailAddress = try? self.keychain.get("appleIDEmailAddress")
            return emailAddress
        }
        set {
           self.keychain["appleIDEmailAddress"] = newValue
        }
    }
    
    var appleIDPassword: String? {
        get {
            let password = try? self.keychain.get("appleIDPassword")
            return password
        }
        set {
            self.keychain["appleIDPassword"] = newValue
        }
    }
    
    var signingCertificatePrivateKey: Data? {
        get {
            let privateKey = try? self.keychain.getData("signingCertificatePrivateKey")
            return privateKey
        }
        set {
            self.keychain[data: "signingCertificatePrivateKey"] = newValue
        }
    }
    
    var signingCertificateSerialNumber: String? {
        get {
            let serialNumber = try? self.keychain.get("signingCertificateSerialNumber")
            return serialNumber
        }
        set {
            self.keychain["signingCertificateSerialNumber"] = newValue
        }
    }
}
