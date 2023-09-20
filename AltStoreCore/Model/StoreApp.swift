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
            
            for screenshot in self.screenshots
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
    
    @nonobjc public var screenshots: [AppScreenshot] {
        return self._screenshots.array as! [AppScreenshot]
    }
    @NSManaged @objc(screenshots) /*private(set)*/ var _screenshots: NSOrderedSet
    
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
            
            let screenshots: [AppScreenshot]
            
            do
            {
                if let screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshots)
                {
                    screenshots = screenshotURLs.map { imageURL in
                        let screenshot = AppScreenshot(imageURL: imageURL, size: nil, context: context)
                        return screenshot
                    }
                }
                else if let screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs)
                {
                    let legacyScreenshotSize = CGSize(width: 750, height: 1334)
                    
                    screenshots = screenshotURLs.map { imageURL in
                        let screenshot = AppScreenshot(imageURL: imageURL, size: legacyScreenshotSize, context: context)
                        return screenshot
                    }
                }
                else
                {
                    screenshots = []
                }
            }
            catch DecodingError.typeMismatch
            {
                // Ignore and fall back to expected format.
                screenshots = try container.decodeIfPresent([AppScreenshot].self, forKey: .screenshots) ?? []
            }
            
            for screenshot in screenshots
            {
                screenshot.appBundleID = self.bundleIdentifier
            }
            
            self.setScreenshots(screenshots)
            
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
            
            // Backwards compatibility
            self.screenshotURLs = []
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
    
    class func makeAltStoreApp(version: String, buildVersion: String?, in context: NSManagedObjectContext) -> StoreApp
    {
        let app = StoreApp(context: context)
        app.name = "AltStore"
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "Riley Testut"
//        app.localizedDescription = "AltStore is an alternative App Store."
        app.localizedDescription = """
AltStore is an alternative app store for non-jailbroken devices.

This version of AltStore allows you to install Delta, an all-in-one emulator for iOS, as well as sideload other .ipa files from the Files app.
"""
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
        appVersion.localizedDescription = """
• “Clear Cache” button removes non-essential data to free up disk space
• Sideload more than 3 apps via MacDirtyCow exploit*†
• Fixes crash when viewing Sources on iOS 12

*Requires iOS 14.0 - 16.1.2 (excluding 15.7.2). iOS 16.2+ not supported.
†Visit faq.altstore.io for detailed instructions.
"""
        try? app.setVersions([appVersion])
        
        let screenshot1 = AppScreenshot(context: context)
        screenshot1.imageURL = URL(string: "https://user-images.githubusercontent.com/705880/78942028-acf54300-7a6d-11ea-821c-5bb7a9b3e73a.PNG")!
        screenshot1._height = 1334
        screenshot1._width = 750
        screenshot1.appBundleID = app.bundleIdentifier
        screenshot1.sourceID = Source.altStoreIdentifier
        
        let screenshot2 = AppScreenshot(context: context)
        screenshot2.imageURL = URL(string: "https://user-images.githubusercontent.com/705880/78942222-0fe6da00-7a6e-11ea-9f2a-dda16157583c.PNG")!
        screenshot2._height = 1334
        screenshot2._width = 750
        screenshot2.appBundleID = app.bundleIdentifier
        screenshot2.sourceID = Source.altStoreIdentifier
        
        let screenshot3 = AppScreenshot(context: context)
        screenshot3.imageURL = URL(string: "https://user-images.githubusercontent.com/705880/65605577-332cba80-df5e-11e9-9f00-b369ce974f71.PNG")!
        screenshot3._height = 1334
        screenshot3._width = 750
        screenshot3.appBundleID = app.bundleIdentifier
        screenshot3.sourceID = Source.altStoreIdentifier
        
        let screenshot4 = AppScreenshot(context: context)
        screenshot4.imageURL = URL(string: "https://f000.backblazeb2.com/file/rileytestut/TestScreenshot1.PNG")!
        screenshot4.appBundleID = app.bundleIdentifier
        screenshot4.sourceID = Source.altStoreIdentifier
        
        let screenshot5 = AppScreenshot(context: context)
        screenshot5.imageURL = URL(string: "https://f000.backblazeb2.com/file/rileytestut/TestScreenshot2.jpeg")!
        screenshot5.appBundleID = app.bundleIdentifier
        screenshot5.sourceID = Source.altStoreIdentifier
        
        app._screenshots = NSOrderedSet(array: [screenshot4, screenshot1, screenshot2, screenshot5, screenshot3])
        
        #if BETA
        app.isBeta = true
        #endif
        
        return app
    }
}
