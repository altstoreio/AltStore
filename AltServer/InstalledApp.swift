//
//  InstalledApp.swift
//  AltServer
//
//  Created by Riley Testut on 5/25/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import Foundation

@objc(ALTInstalledApp) @objcMembers
class InstalledApp: NSObject, MenuDisplayable
{
    let name: String
    let bundleIdentifier: String
    let executableName: String
    
    init?(dictionary: [String: Any])
    {
        guard let name = dictionary[kCFBundleNameKey as String] as? String,
              let bundleIdentifier = dictionary[kCFBundleIdentifierKey as String] as? String,
              let executableName = dictionary[kCFBundleExecutableKey as String] as? String
        else { return nil }
        
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
    }
}
