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
        guard let appGroup = Bundle.main.altstoreAppGroup else { return .standard }
        
        let sharedUserDefaults = UserDefaults(suiteName: appGroup)!
        return sharedUserDefaults
    }()
    
    @NSManaged var firstLaunch: Date?
    @NSManaged var requiresAppGroupMigration: Bool
    
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
    
    @nonobjc
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
    
    @NSManaged var ignoreActiveAppsLimit: Bool
    
    // Including "MacDirtyCow" in name triggers false positives with malware detectors 🤷‍♂️
    @NSManaged var isCowExploitSupported: Bool
    
    @NSManaged var permissionCheckingDisabled: Bool
    
    class func registerDefaults()
    {
        let ios13_5 = OperatingSystemVersion(majorVersion: 13, minorVersion: 5, patchVersion: 0)
        let isLegacyDeactivationSupported = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        let activeAppLimitIncludesExtensions = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        
        let ios14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        let localServerSupportsRefreshing = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14)
        
        let ios16 = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        let ios16_2 = OperatingSystemVersion(majorVersion: 16, minorVersion: 2, patchVersion: 0)
        let ios15_7_2 = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 2)
        
        // MacDirtyCow supports iOS 14.0 - 15.7.1 OR 16.0 - 16.1.2
        let isMacDirtyCowSupported =
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios15_7_2)) ||
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16_2))
        
        #if DEBUG
        let permissionCheckingDisabled = true
        #else
        let permissionCheckingDisabled = false
        #endif
        
        let defaults = [
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.isLegacyDeactivationSupported): isLegacyDeactivationSupported,
            #keyPath(UserDefaults.activeAppLimitIncludesExtensions): activeAppLimitIncludesExtensions,
            #keyPath(UserDefaults.localServerSupportsRefreshing): localServerSupportsRefreshing,
            #keyPath(UserDefaults.requiresAppGroupMigration): true,
            #keyPath(UserDefaults.ignoreActiveAppsLimit): false,
            #keyPath(UserDefaults.isCowExploitSupported): isMacDirtyCowSupported,
            #keyPath(UserDefaults.permissionCheckingDisabled): permissionCheckingDisabled,
        ]
        
        UserDefaults.standard.register(defaults: defaults)
        UserDefaults.shared.register(defaults: defaults)
        
        if !isMacDirtyCowSupported
        {
            // Disable ignoreActiveAppsLimit if running iOS version that doesn't support MacDirtyCow.
            UserDefaults.standard.ignoreActiveAppsLimit = false
        }
    }
}
