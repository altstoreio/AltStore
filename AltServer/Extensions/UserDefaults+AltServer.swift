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
    private static let anisetteServerURLKey = "AnisetteServerURL"
    
    var altJITTimeout: TimeInterval? {
        let timeout = self.double(forKey: UserDefaults.altJITTimeoutKey) // Coerces strings into doubles.
        guard timeout != 0 else { return nil }
        
        return timeout
    }
    
    var anisetteServerURL: URL? {
        // ALTSERVER_ANISETTE_SERVER matches AltServer-Linux, and wins over the preference when launched from a shell.
        guard let urlString = ProcessInfo.processInfo.environment["ALTSERVER_ANISETTE_SERVER"] ?? self.string(forKey: UserDefaults.anisetteServerURLKey), !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}
