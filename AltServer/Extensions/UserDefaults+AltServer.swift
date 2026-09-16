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

    // The remote anisette server that last worked, so we keep reusing the identity we provisioned with it.
    var preferredAnisetteServerURL: URL? {
        get {
            return self.url(forKey: "preferredAnisetteServerURL")
        }
        set {
            self.set(newValue, forKey: "preferredAnisetteServerURL")
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
    private static let disableRemoteAnisetteKey = "DisableRemoteAnisette"

    var altJITTimeout: TimeInterval? {
        let timeout = self.double(forKey: UserDefaults.altJITTimeoutKey) // Coerces strings into doubles.
        guard timeout != 0 else { return nil }

        return timeout
    }

    // `defaults write com.rileytestut.AltServer AnisetteServerURL https://ani.sidestore.io`
    // Pins the remote anisette server instead of picking one from AltStore's published list.
    var anisetteServerURL: URL? {
        guard let urlString = self.string(forKey: UserDefaults.anisetteServerURLKey),
              let url = URL(string: urlString), url.host != nil
        else { return nil }

        return url
    }

    // `defaults write com.rileytestut.AltServer DisableRemoteAnisette -bool YES`
    // Opts out of contacting a remote anisette server when AOSKit can't provide anisette data.
    var disablesRemoteAnisette: Bool {
        return self.bool(forKey: UserDefaults.disableRemoteAnisetteKey)
    }
}
