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
    
    var altJITTimeout: TimeInterval? {
        let timeout = self.double(forKey: UserDefaults.altJITTimeoutKey) // Coerces strings into doubles.
        guard timeout != 0 else { return nil }
        
        return timeout
    }
}
