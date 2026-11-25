//
//  UserDefaults+AltServer.swift
//  AltServer
//
//  Created by Riley Testut on 7/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension UserDefaults
{
    var serverID: String? {
        get {
            return self.string(forKey: "serverID")
        }
        set {
            self.set(newValue, forKey: "serverID")
        }
    }
    
    var anisetteID: String? {
        get {
            return self.string(forKey: "anisetteID")
        }
        set {
            self.set(newValue, forKey: "anisetteID")
        }
    }
    
    var preferredAnisetteServerURL: URL? {
        get {
            return self.string(forKey: "preferredAnisetteServerURL").flatMap { URL(string: $0) }
        }
        set {
            self.set(newValue?.absoluteString, forKey: "preferredAnisetteServerURL")
        }
    }

    var didPresentInitialNotification: Bool {
        get {
            return self.bool(forKey: "didPresentInitialNotification")
        }
        set {
            self.set(newValue, forKey: "didPresentInitialNotification")
        }
    }
    
    func registerDefaults()
    {
        if self.serverID == nil
        {
            self.serverID = UUID().uuidString
        }
    }
}

// "Public" defaults configurable via CLI.
extension UserDefaults
{
    private static let altJITTimeoutKey = "JITTimeout"
    private static let anisetteServerURLKey = "RemoteAltServerURL"
    private static let usesAnisetteServerClientInfoKey = "UseAnisetteServerClientInfo"
    
    var altJITTimeout: TimeInterval? {
        let timeout = self.double(forKey: UserDefaults.altJITTimeoutKey) // Coerces strings into doubles.
        guard timeout != 0 else { return nil }
        
        return timeout
    }
    
    var anisetteServerURLOverride: URL? {
        return self.string(forKey: UserDefaults.anisetteServerURLKey).flatMap { URL(string: $0) }
    }
    
    // Opts out of identifying as this Mac, and uses the anisette server's (outdated) client info instead.
    var usesAnisetteServerClientInfo: Bool {
        return self.bool(forKey: UserDefaults.usesAnisetteServerClientInfoKey)
    }
}
