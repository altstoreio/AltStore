//
//  UserDefaults+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 6/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

import Roxas

extension UserDefaults
{
    @NSManaged var firstLaunch: Date?
    
    @NSManaged var preferredServerID: String?
    
    @NSManaged var isBackgroundRefreshEnabled: Bool
    @NSManaged var isDebugModeEnabled: Bool
    @NSManaged var presentedLaunchReminderNotification: Bool
    
    @NSManaged var legacySideloadedApps: [String]?
    
    func registerDefaults()
    {
        self.register(defaults: [#keyPath(UserDefaults.isBackgroundRefreshEnabled): true])
    }
}
