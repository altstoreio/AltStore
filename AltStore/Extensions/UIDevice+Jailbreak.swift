//
//  UIDevice+Jailbreak.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import ARKit

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
    
    var supportsFugu14: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        // Fugu14 is supported on devices with an A12 processor or better.
        // ARKit 3 is only supported by devices with an A12 processor or better, according to the documentation.
        return ARBodyTrackingConfiguration.isSupported
        #endif
    }
    
    var isUntetheredJailbreakRequired: Bool {
        let ios14_4 = OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 0)
        
        let isUntetheredJailbreakRequired = ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14_4)
        return isUntetheredJailbreakRequired
    }
}
