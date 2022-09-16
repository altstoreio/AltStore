//
//  UserDefaults+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 6/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

import Roxas

public extension UserDefaults
{
    static let shared: UserDefaults = {
        guard let appGroup = Bundle.main.appGroups.first else { return .standard }
        
        let sharedUserDefaults = UserDefaults(suiteName: appGroup)!
        return sharedUserDefaults
    }()
    
    @NSManaged var firstLaunch: Date?
    @NSManaged var requiresAppGroupMigration: Bool
    @NSManaged var customAnisetteURL: String?
    @NSManaged var preferredServerID: String?
    
    @NSManaged var isBackgroundRefreshEnabled: Bool
    @NSManaged var isDebugModeEnabled: Bool
    @NSManaged var presentedLaunchReminderNotification: Bool
    
    @NSManaged var legacySideloadedApps: [String]?
    
    @NSManaged var isLegacyDeactivationSupported: Bool
    @NSManaged var activeAppLimitIncludesExtensions: Bool
    
    @NSManaged var localServerSupportsRefreshing: Bool
    
    @NSManaged var patchedApps: [String]?
    
    @NSManaged var patronsRefreshID: String?
    
    @NSManaged var trustedSourceIDs: [String]?
    
    var activeAppsLimit: Int? {
        get {
            return self._activeAppsLimit?.intValue
        }
        set {
            if let value = newValue
            {
                self._activeAppsLimit = NSNumber(value: value)
            }
            else
            {
                self._activeAppsLimit = nil
            }
        }
    }
    @NSManaged @objc(activeAppsLimit) private var _activeAppsLimit: NSNumber?
    
    class func registerDefaults()
    {
        let ios13_5 = OperatingSystemVersion(majorVersion: 13, minorVersion: 5, patchVersion: 0)
        let isLegacyDeactivationSupported = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        let activeAppLimitIncludesExtensions = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        
        let ios14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        let localServerSupportsRefreshing = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14)
        
        let defaults = [
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.isLegacyDeactivationSupported): isLegacyDeactivationSupported,
            #keyPath(UserDefaults.activeAppLimitIncludesExtensions): activeAppLimitIncludesExtensions,
            #keyPath(UserDefaults.localServerSupportsRefreshing): localServerSupportsRefreshing,
            #keyPath(UserDefaults.requiresAppGroupMigration): true
        ]
        
        UserDefaults.standard.register(defaults: defaults)
        UserDefaults.shared.register(defaults: defaults)
    }
}
