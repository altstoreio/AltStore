//
//  ALTApplication+AltStoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 11/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import AltSign

extension ALTApplication
{
    static let altstoreBundleID = "com.rileytestut.AltStore"
    
    // Phone-only profile refresh cannot update profiles on a paired Watch.
    var containsWatchApp: Bool {
        return self.nestedApplications.contains { $0.isWatchOSApplication }
    }

    var isAltStoreApp: Bool {
        let isAltStoreApp = self.bundleIdentifier.contains(ALTApplication.altstoreBundleID)
        return isAltStoreApp
    }
}
