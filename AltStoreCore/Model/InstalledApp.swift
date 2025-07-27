//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import MarketplaceKit

import AltSign

extension InstalledApp
{
    public static var freeAccountActiveAppsLimit: Int {
        if UserDefaults.standard.ignoreActiveAppsLimit
        {
            // MacDirtyCow exploit allows users to remove 3-app limit, so return 10 to match App ID limit per-week.
            // Don't return nil because that implies there is no limit, which isn't quite true due to App ID limit.
            return 10
        }
        else
        {
            // Free developer accounts are limited to only 3 active sideloaded apps at a time as of iOS 13.3.1.
            return 3
        }
    }
}

public protocol InstalledAppProtocol: Fetchable
{
    var name: String { get }
    var bundleIdentifier: String { get }
    var resignedBundleIdentifier: String { get }
    var version: String { get }
    
    var refreshedDate: Date { get }
    var expirationDate: Date { get }
    var installedDate: Date { get }
}

@objc(InstalledApp)
public class InstalledApp: NSManagedObject, InstalledAppProtocol, @unchecked Sendable
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var version: String
    @NSManaged public var buildVersion: String
    
    //TODO: Add separate modifiedDate? Or re-purpose refreshedDate for MARKETPLACE builds?
    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date
    
    @NSManaged public var isActive: Bool
    @NSManaged public var needsResign: Bool
    @NSManaged public var hasAlternateIcon: Bool
    
    @NSManaged public var certificateSerialNumber: String?
    @NSManaged public var storeBuildVersion: String?
    
    /* Transient */
    @NSManaged public var isRefreshing: Bool
    
    /* Relationships */
    @NSManaged public var storeApp: StoreApp?
    @NSManaged public var team: Team?
    @NSManaged public var appExtensions: Set<InstalledExtension>
    
    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.
    
    public var isSideloaded: Bool {
        return self.storeApp == nil
    }
    
    public var appIDCount: Int {
        return 1 + self.appExtensions.count
    }
    
    public var requiredActiveSlots: Int {
        let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? self.appIDCount : 1
        return requiredActiveSlots
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(resignedApp: ALTApplication, originalBundleIdentifier: String, certificateSerialNumber: String?, storeBuildVersion: String?, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        
        // In practice this update() is redundant because we always call update() again after init from callers,
        // but better to have an init that is guaranteed to successfully initialize an object
        // than one that has a hidden assumption a second method will be called.
        self.update(resignedApp: resignedApp, certificateSerialNumber: certificateSerialNumber, storeBuildVersion: storeBuildVersion)
    }
    
    public init(marketplaceApp: StoreApp, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.name = marketplaceApp.name
        self.bundleIdentifier = marketplaceApp.bundleIdentifier
        self.resignedBundleIdentifier = marketplaceApp.bundleIdentifier
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        self.expirationDate = Date.distantFuture
    }
}

public extension InstalledApp
{
    var localizedVersion: String {
        guard let storeBuildVersion else { return self.version }
        
        if let installedVersion = self.storeApp?._versions.lazy.compactMap({ $0 as? AltStoreCore.AppVersion }).first(where: { $0.version == self.version && $0.buildVersion == storeBuildVersion }),
           let marketingVersion = installedVersion.marketingVersion
        {
            return marketingVersion
        }
        
        let localizedVersion = "\(self.version) (\(storeBuildVersion))"
        return localizedVersion
    }
    
    func update(resignedApp: ALTApplication, certificateSerialNumber: String?, storeBuildVersion: String?)
    {
        self.name = resignedApp.name
        
        self.resignedBundleIdentifier = resignedApp.bundleIdentifier
        self.version = resignedApp.version
        self.buildVersion = resignedApp.buildVersion
        self.storeBuildVersion = storeBuildVersion
        
        self.certificateSerialNumber = certificateSerialNumber
        
        if let provisioningProfile = resignedApp.provisioningProfile
        {
            self.update(provisioningProfile: provisioningProfile)
        }
    }
    
    @available(iOS 17.4, *)
    func update(forMarketplaceAppVersion appVersion: AppVersion)
    {
        //TODO: Switch to receiving AppLibrary.App.Metadata once that's reliable.
        
        self.version = appVersion.version
        self.buildVersion = appVersion.buildVersion ?? ""
        self.refreshedDate = Date() // Effectively becomes "modified date"
        
        self.storeBuildVersion = appVersion.buildVersion
        
        if let storeApp = appVersion.storeApp
        {
            self.name = storeApp.name
            self.storeApp = storeApp
        }
    }
    
    func update(provisioningProfile: ALTProvisioningProfile)
    {
        self.refreshedDate = provisioningProfile.creationDate
        self.expirationDate = provisioningProfile.expirationDate
    }
    
    func matches(_ appVersion: AppVersion) -> Bool
    {
        let matchesAppVersion = (self.version == appVersion.version && self.storeBuildVersion == appVersion.buildVersion)
        return matchesAppVersion
    }
}

public extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
    
    class func supportedUpdatesFetchRequest() -> NSFetchRequest<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        
        let predicateFormat = [
            // isActive && storeApp != nil && latestSupportedVersion != nil
            "%K == YES AND %K != nil AND %K != nil",
            
            "AND",
            
            // latestSupportedVersion.version != installedApp.version || latestSupportedVersion.buildVersion != installedApp.storeBuildVersion
            //
            // We have to also check !(latestSupportedVersion.buildVersion == '' && installedApp.storeBuildVersion == nil)
            // because latestSupportedVersion.buildVersion stores an empty string for nil, while installedApp.storeBuildVersion uses NULL.
            "(%K != %K OR (%K != %K AND NOT (%K == '' AND %K == nil)))",
            
            "AND",
            
            // !isPledgeRequired || isPledged
            "(%K == NO OR %K == YES)"
        ].joined(separator: " ")
        
        fetchRequest.predicate = NSPredicate(format: predicateFormat,
                                             #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.latestSupportedVersion),
                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion.version), #keyPath(InstalledApp.version),
                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion), #keyPath(InstalledApp.storeBuildVersion),
                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion), #keyPath(InstalledApp.storeBuildVersion),
                                             #keyPath(InstalledApp.storeApp.isPledgeRequired), #keyPath(InstalledApp.storeApp.isPledged))
        return fetchRequest
    }
    
    class func activeAppsFetchRequest() -> NSFetchRequest<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive))
        return fetchRequest
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        let altStore = InstalledApp.first(satisfying: predicate, in: context)
        return altStore
    }
    
    class func fetchActiveApps(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        let activeApps = InstalledApp.fetch(InstalledApp.activeAppsFetchRequest(), in: context)
        return activeApps
    }
    
    class func fetchAppsForRefreshingAll(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        let predicate = NSPredicate(format: "(%K == YES AND %K != %@) AND (%K == nil OR %K == NO OR %K == YES)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(InstalledApp.storeApp),
                                    #keyPath(InstalledApp.storeApp.isPledgeRequired),
                                    #keyPath(InstalledApp.storeApp.isPledged))
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context)
        {
            // Refresh AltStore last since it causes app to quit.
            
            if let storeApp = altStoreApp.storeApp
            {
                if !storeApp.isPledgeRequired || storeApp.isPledged
                {
                    // Only add AltStore if it's the public version OR if it's the beta and we're pledged to it.
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                // No associated storeApp, so add it just to be safe.
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
    
    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        // Date 6 hours before now.
        let date = Date().addingTimeInterval(-1 * 6 * 60 * 60)
        
        let predicate = NSPredicate(format: "(%K == YES) AND (%K < %@) AND (%K != %@) AND (%K == nil OR %K == NO OR %K == YES)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(InstalledApp.storeApp),
                                    #keyPath(InstalledApp.storeApp.isPledgeRequired),
                                    #keyPath(InstalledApp.storeApp.isPledged)
        )
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context), altStoreApp.refreshedDate < date
        {
            if let storeApp = altStoreApp.storeApp
            {
                if !storeApp.isPledgeRequired || storeApp.isPledged
                {
                    // Only add AltStore if it's the public version OR if it's the beta and we're pledged to it.
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                // No associated storeApp, so add it just to be safe.
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
}

public extension InstalledApp
{
    var openAppURL: URL {
        let openAppURL = URL(string: "altstore-" + self.bundleIdentifier + "://")!
        return openAppURL
    }
    
    class func openAppURL(for app: AppProtocol) -> URL
    {
        let openAppURL = URL(string: "altstore-" + app.bundleIdentifier + "://")!
        return openAppURL
    }
    
    var isUpdateAvailable: Bool {
        guard let storeApp = self.storeApp, let latestVersion = storeApp.latestSupportedVersion else { return false }
        guard !storeApp.isPledgeRequired || storeApp.isPledged else { return false }
        
        let isUpdateAvailable = !self.matches(latestVersion)
        return isUpdateAvailable
    }
}

public extension InstalledApp
{
    class var appsDirectoryURL: URL {
        let baseDirectory = FileManager.default.altstoreSharedDirectory ?? FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        
        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return appsDirectoryURL
    }
    
    class var legacyAppsDirectoryURL: URL {
        let baseDirectory = FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        return appsDirectoryURL
    }
    
    class func fileURL(for app: AppProtocol) -> URL
    {
        let appURL = self.directoryURL(for: app).appendingPathComponent("App.app")
        return appURL
    }
    
    class func refreshedIPAURL(for app: AppProtocol) -> URL
    {
        let ipaURL = self.directoryURL(for: app).appendingPathComponent("Refreshed.ipa")
        return ipaURL
    }
    
    class func directoryURL(for app: AppProtocol) -> URL
    {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.bundleIdentifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
        return directoryURL
    }
    
    class func installedAppUTI(forBundleIdentifier bundleIdentifier: String) -> String
    {
        let installedAppUTI = "io.altstore.Installed." + bundleIdentifier
        return installedAppUTI
    }
    
    class func installedBackupAppUTI(forBundleIdentifier bundleIdentifier: String) -> String
    {
        let installedBackupAppUTI = InstalledApp.installedAppUTI(forBundleIdentifier: bundleIdentifier) + ".backup"
        return installedBackupAppUTI
    }
    
    class func alternateIconURL(for app: AppProtocol) -> URL
    {
        let installedBackupAppUTI = self.directoryURL(for: app).appendingPathComponent("AltIcon.png")
        return installedBackupAppUTI
    }
    
    var directoryURL: URL {
        return InstalledApp.directoryURL(for: self)
    }
    
    var fileURL: URL {
        return InstalledApp.fileURL(for: self)
    }
    
    var refreshedIPAURL: URL {
        return InstalledApp.refreshedIPAURL(for: self)
    }
    
    var installedAppUTI: String {
        return InstalledApp.installedAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    var installedBackupAppUTI: String {
        return InstalledApp.installedBackupAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    var alternateIconURL: URL {
        return InstalledApp.alternateIconURL(for: self)
    }
}
