//
//  UIDevice+Jailbreak.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

extension UIDevice
{
    var isJailbroken: Bool {
        if
            FileManager.default.fileExists(atPath: "/Applications/Cydia.app") ||
            FileManager.default.fileExists(atPath: "/Library/MobileSubstrate/MobileSubstrate.dylib") ||
            FileManager.default.fileExists(atPath: "/bin/bash") ||
            FileManager.default.fileExists(atPath: "/usr/sbin/sshd") ||
            FileManager.default.fileExists(atPath: "/etc/apt") ||
            FileManager.default.fileExists(atPath: "/private/var/lib/apt/") ||
            UIApplication.shared.canOpenURL(URL(string:"cydia://")!)
        {
            return true
        }
        else
        {
            return false
        }
    }
}
