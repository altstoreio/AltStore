//
//  StoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import Roxas
import AltSign

public extension StoreApp
{
    #if ALPHA
    static let altstoreAppID = "com.rileytestut.AltStore.Alpha"
    #elseif BETA
    static let altstoreAppID = "com.rileytestut.AltStore.Beta"
    #else
    static let altstoreAppID = "com.rileytestut.AltStore"
    #endif
    
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
    
    private struct PatreonParameters: Decodable
    {
        var pledge: Decimal?
        var currency: String?
        var tiers: Set<String>?
        var benefit: String?
    }
}

@objc(StoreApp)
public class StoreApp: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var name: String
    @NSManaged public private(set) var bundleIdentifier: String
    @NSManaged public private(set) var subtitle: String?
    
    @NSManaged public private(set) var developerName: String
    @NSManaged public private(set) var localizedDescription: String
    @NSManaged @objc(size) internal var _size: Int32
    
    @NSManaged public private(set) var iconURL: URL
    @NSManaged public private(set) var screenshotURLs: [URL]
    
    @NSManaged @objc(downloadURL) internal var _downloadURL: URL
    @NSManaged public private(set) var tintColor: UIColor?
    @NSManaged public private(set) var isBeta: Bool
    
    @NSManaged public private(set) var isPledgeRequired: Bool
    @NSManaged public internal(set) var isPledged: Bool
    @NSManaged public internal(set) var pledgeCurrency: String?
    
    @nonobjc public var pledgeAmount: Decimal? { _pledgeAmount as? Decimal }
    @NSManaged @objc(pledgeAmount) private var _pledgeAmount: NSDecimalNumber?
    
    @NSManaged public var sortIndex: Int32
    
    @objc public internal(set) var sourceIdentifier: String? {
        get {
            self.willAccessValue(forKey: #keyPath(sourceIdentifier))
            defer { self.didAccessValue(forKey: #keyPath(sourceIdentifier)) }
            
            let sourceIdentifier = self.primitiveSourceIdentifier
            return sourceIdentifier
        }
        set {
            self.willChangeValue(forKey: #keyPath(sourceIdentifier))
            self.primitiveSourceIdentifier = newValue
            self.didChangeValue(forKey: #keyPath(sourceIdentifier))
            
            for version in self.versions
            {
                version.sourceID = newValue
            }
            
            for permission in self.permissions
            {
                permission.sourceID = self.sourceIdentifier ?? ""
            }
            
            for screenshot in self.allScreenshots
            {
                screenshot.sourceID = self.sourceIdentifier ?? ""
            }
        }
    }
    @NSManaged private var primitiveSourceIdentifier: String?
    
    // Legacy (kept for backwards compatibility)
    @NSManaged @objc(version) internal private(set) var _version: String
    @NSManaged @objc(versionDate) internal private(set) var _versionDate: Date
    @NSManaged @objc(versionDescription) internal private(set) var _versionDescription: String?
    
    /* Relationships */
    @NSManaged public var installedApp: InstalledApp?
    @NSManaged public var newsItems: Set<NewsItem>
    
    @NSManaged @objc(source) public var _source: Source?
    @NSManaged public internal(set) var featuringSource: Source?
    
    @NSManaged @objc(latestVersion) public private(set) var latestSupportedVersion: AppVersion?
    @NSManaged @objc(versions) public private(set) var _versions: NSOrderedSet
    
    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.
    
    @nonobjc public var source: Source? {
        set {
            self._source = newValue
            self.sourceIdentifier = newValue?.identifier
        }
        get {
            return self._source
        }
    }
    
    @nonobjc public var permissions: Set<AppPermission> {
        return self._permissions as! Set<AppPermission>
    }
    @NSManaged @objc(permissions) internal private(set) var _permissions: NSSet // Use NSSet to avoid eagerly fetching values.
    
    @nonobjc public var versions: [AppVersion] {
        return self._versions.array as! [AppVersion]
    }
    
    @nonobjc public var allScreenshots: [AppScreenshot] {
        return self._screenshots.array as! [AppScreenshot]
    }
    @NSManaged @objc(screenshots) private(set) var _screenshots: NSOrderedSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case bundleIdentifier
        case developerName
        case localizedDescription
        case iconURL
        case screenshots
        case tintColor
        case subtitle
        case permissions = "appPermissions"
        case size
        case isBeta = "beta"
        case versions
        case patreon
        
        // Legacy
        case version
        case versionDescription
        case versionDate
        case downloadURL
        case screenshotURLs
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: StoreApp.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            self.developerName = try container.decode(String.self, forKey: .developerName)
            self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
            
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            
            self.iconURL = try container.decode(URL.self, forKey: .iconURL)
            
            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                
                self.tintColor = tintColor
            }
            
            self.isBeta = try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false
            
            let appScreenshots: [AppScreenshot]
            
            if let screenshots = try container.decodeIfPresent(AppScreenshots.self, forKey: .screenshots)
            {
                appScreenshots = screenshots.screenshots
            }
            else if let screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs)
            {
                // Assume 9:16 iPhone 8 screen dimensions for legacy screenshotURLs.
                let legacyAspectRatio = CGSize(width: 750, height: 1334)
                
                appScreenshots = screenshotURLs.map { imageURL in
                    let screenshot = AppScreenshot(imageURL: imageURL, size: legacyAspectRatio, deviceType: .iphone, context: context)
                    return screenshot
                }
            }
            else
            {
                appScreenshots = []
            }
   
            for screenshot in appScreenshots
            {
                screenshot.appBundleID = self.bundleIdentifier
            }
            
            self.setScreenshots(appScreenshots)
            
            if let appPermissions = try container.decodeIfPresent(AppPermissions.self, forKey: .permissions)
            {
                let allPermissions = appPermissions.entitlements + appPermissions.privacy
                for permission in allPermissions
                {
                    permission.appBundleID = self.bundleIdentifier
                }
                
                self._permissions = NSSet(array: allPermissions)
            }
            else
            {
                self._permissions = NSSet()
            }
            
            if let versions = try container.decodeIfPresent([AppVersion].self, forKey: .versions)
            {
                for version in versions
                {
                    version.appBundleID = self.bundleIdentifier
                }
                
                try self.setVersions(versions)
            }
            else
            {
                let version = try container.decode(String.self, forKey: .version)
                let versionDate = try container.decode(Date.self, forKey: .versionDate)
                let versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
                
                let downloadURL = try container.decode(URL.self, forKey: .downloadURL)
                let size = try container.decode(Int32.self, forKey: .size)
                
                let appVersion = AppVersion.makeAppVersion(version: version,
                                                           buildVersion: nil,
                                                           date: versionDate,
                                                           localizedDescription: versionDescription,
                                                           downloadURL: downloadURL,
                                                           size: Int64(size),
                                                           appBundleID: self.bundleIdentifier,
                                                           in: context)
                try self.setVersions([appVersion])
            }
            
            if let patreon = try container.decodeIfPresent(PatreonParameters.self, forKey: .patreon)
            {
                self.isPledgeRequired = true
                
                if patreon.pledge == nil && patreon.tiers == nil && patreon.benefit == nil
                {
                    // No conditions, so assign internal pledgeAmount of 0 to simplify logic
                    self._pledgeAmount = 0 as NSDecimalNumber
                }
                else
                {
                    self._pledgeAmount = patreon.pledge as? NSDecimalNumber
                }
                
                self.pledgeCurrency = patreon.currency ?? "USD" // Default to US Dollar
                
                if let patreonAccount = decoder.patreonAccount
                {
                    if let tierIDs = patreon.tiers
                    {
                        let tier = patreonAccount.pledges.flatMap { $0.tiers }.first { tierIDs.contains($0.identifier) }
                        if tier != nil
                        {
                            // Only assign isPledged to true, otherwise leave alone to prevent replacing earlier check
                            self.isPledged = true
                        }
                    }
                    
                    if let rewardID = patreon.benefit
                    {
                        let reward = patreonAccount.pledges.flatMap { $0.rewards }.first { $0.identifier == rewardID }
                        if reward != nil
                        {
                            // Only assign isPledged to true, otherwise leave alone to prevent replacing earlier check
                            self.isPledged = true
                        }
                    }
                }
            }
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

internal extension StoreApp
{
    func setVersions(_ versions: [AppVersion]) throws
    {
        guard let latestVersion = versions.first else {
            throw MergeError.noVersions(for: self)
        }
        
        self._versions = NSOrderedSet(array: versions)
        
        let latestSupportedVersion = versions.first(where: { $0.isSupported })
        self.latestSupportedVersion = latestSupportedVersion
        
        for case let version as AppVersion in self._versions
        {
            if version == latestSupportedVersion
            {
                version.latestSupportedVersionApp = self
            }
            else
            {
                // Ensure we replace any previous relationship when merging.
                version.latestSupportedVersionApp = nil
            }
        }
                
        // Preserve backwards compatibility by assigning legacy property values.
        self._version = latestVersion.version
        self._versionDate = latestVersion.date
        self._versionDescription = latestVersion.localizedDescription
        self._downloadURL = latestVersion.downloadURL
        self._size = Int32(latestVersion.size)
    }
    
    func setPermissions(_ permissions: Set<AppPermission>)
    {
        for case let permission as AppPermission in self._permissions
        {
            if permissions.contains(permission)
            {
                permission.app = self
            }
            else
            {
                permission.app = nil
            }
        }
        
        self._permissions = permissions as NSSet
    }
    
    func setScreenshots(_ screenshots: [AppScreenshot])
    {
        for case let screenshot as AppScreenshot in self._screenshots
        {
            if screenshots.contains(screenshot)
            {
                screenshot.app = self
            }
            else
            {
                screenshot.app = nil
            }
        }
        
        self._screenshots = NSOrderedSet(array: screenshots)
        
        // Backwards compatibility
        self.screenshotURLs = screenshots.map { $0.imageURL }
    }
}

public extension StoreApp
{
    func screenshots(for deviceType: ALTDeviceType) -> [AppScreenshot]
    {
        //TODO: Support multiple device types
        let filteredScreenshots = self.allScreenshots.filter { $0.deviceType == deviceType }
        return filteredScreenshots
    }
    
    func preferredScreenshots() -> [AppScreenshot]
    {
        let deviceType: ALTDeviceType
        
        if UIDevice.current.model.contains("iPad")
        {
            deviceType = .ipad
        }
        else
        {
            deviceType = .iphone
        }
        
        let preferredScreenshots = self.screenshots(for: deviceType)
        guard !preferredScreenshots.isEmpty else {
            // There are no screenshots for deviceType, so return _all_ screenshots instead.
            return self.allScreenshots
        }
        
        return preferredScreenshots
    }
}

public extension StoreApp
{
    var latestAvailableVersion: AppVersion? {
        return self._versions.firstObject as? AppVersion
    }
    
    var globallyUniqueID: String? {
        guard let sourceIdentifier = self.sourceIdentifier else { return nil }
        
        let globallyUniqueID = self.bundleIdentifier + "|" + sourceIdentifier
        return globallyUniqueID
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp>
    {
        return NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }
    
    class var availableAppsPredicate: NSPredicate {
        let predicate = NSPredicate(format: "(%K == NO) OR (%K == YES AND %K == YES)",
                                    #keyPath(StoreApp.isPledgeRequired),
                                    #keyPath(StoreApp.isPledgeRequired), #keyPath(StoreApp.isPledged))
        return predicate
    }
    
    class var nonPatreonAppsPredicate: NSPredicate {
        let predicate = NSPredicate(format: "%K == NO", #keyPath(StoreApp.isPledgeRequired))
        return predicate
    }
    
    class func makeAltStoreApp(version: String, buildVersion: String?, in context: NSManagedObjectContext) -> StoreApp
    {
        let app = StoreApp(context: context)
        app.name = "AltStore"
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "Riley Testut"
        app.localizedDescription = "AltStore is an alternative App Store."
        app.iconURL = URL(string: "https://user-images.githubusercontent.com/705880/63392210-540c5980-c37b-11e9-968c-8742fc68ab2e.png")!
        app.screenshotURLs = []
        app.sourceIdentifier = Source.altStoreIdentifier
        
        let appVersion = AppVersion.makeAppVersion(version: version,
                                                   buildVersion: buildVersion,
                                                   date: Date(),
                                                   downloadURL: URL(string: "http://rileytestut.com")!,
                                                   size: 0,
                                                   appBundleID: app.bundleIdentifier,
                                                   sourceID: Source.altStoreIdentifier,
                                                   in: context)
        try? app.setVersions([appVersion])
        
        #if BETA
        app.isBeta = true
        #endif
        
        return app
    }
}
