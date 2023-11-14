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
    
    @NSManaged var skipPatreonDownloads: Bool
    
    @nonobjc var preferredAppSorting: AppSorting {
        get {
            let sorting = _preferredAppSorting.flatMap { AppSorting(rawValue: $0) } ?? .name
            return sorting
        }
        set {
            _preferredAppSorting = newValue.rawValue
        }
    }
    @NSManaged @objc(preferredAppSorting) private var _preferredAppSorting: String?
    
    @nonobjc var preferredSortOrders: [AppSorting: AppSortOrder] {
        get {
            guard let rawSortOrders = _preferredSortOrders as? [String: Int] else { return [:] }
            
            let sortOrders = rawSortOrders.compactMap { (rawSorting, rawSortOrder) -> (AppSorting, AppSortOrder?)? in
                guard let sorting = AppSorting(rawValue: rawSorting) else { return nil }
                return (sorting, AppSortOrder(rawValue: rawSortOrder))
            }.reduce(into: [AppSorting: AppSortOrder]()) { $0[$1.0] = $1.1 }
            return sortOrders
        }
        set {
            let rawSortOrders = newValue.map { ($0.key.rawValue as String, $0.value.rawValue) }.reduce(into: [String: Int]()) { $0[$1.0] = $1.1 }
            _preferredSortOrders = rawSortOrders as NSDictionary
        }
    }
    @NSManaged @objc(preferredSortOrders) private var _preferredSortOrders: NSDictionary?
    
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
    @NSManaged var responseCachingDisabled: Bool
    
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
        
        // Pre-iOS 15 doesn't support custom sorting, so default to sorting by name.
        // Otherwise, default to sorting by last updated.
        let preferredAppSorting: AppSorting = if #available(iOS 15, *) { .lastUpdated } else { .name }
        
        let defaults = [
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.isLegacyDeactivationSupported): isLegacyDeactivationSupported,
            #keyPath(UserDefaults.activeAppLimitIncludesExtensions): activeAppLimitIncludesExtensions,
            #keyPath(UserDefaults.localServerSupportsRefreshing): localServerSupportsRefreshing,
            #keyPath(UserDefaults.requiresAppGroupMigration): true,
            #keyPath(UserDefaults.ignoreActiveAppsLimit): false,
            #keyPath(UserDefaults.isCowExploitSupported): isMacDirtyCowSupported,
            #keyPath(UserDefaults.permissionCheckingDisabled): permissionCheckingDisabled,
            #keyPath(UserDefaults._preferredAppSorting): preferredAppSorting.rawValue,
        ] as [String: Any]
        
        UserDefaults.standard.register(defaults: defaults)
        UserDefaults.shared.register(defaults: defaults)
        
        if !isMacDirtyCowSupported
        {
            // Disable ignoreActiveAppsLimit if running iOS version that doesn't support MacDirtyCow.
            UserDefaults.standard.ignoreActiveAppsLimit = false
        }
        
        #if !BETA
        UserDefaults.standard.responseCachingDisabled = false
        #endif
    }
}
