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
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #elseif BETA
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #else
    static let altstoreAppID = Bundle.Info.appbundleIdentifier
    #endif
    
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
}

@objc
public enum Platform: UInt, Codable {
    case ios
    case tvos
    case macos
}

@objc
public final class PlatformURL: NSManagedObject, Decodable {
    /* Properties */
    @NSManaged public private(set) var platform: Platform
    @NSManaged public private(set) var downloadURL: URL
    
    
    private enum CodingKeys: String, CodingKey
    {
        case platform
        case downloadURL
    }
    
    
    public init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: PlatformURL.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.platform = try container.decode(Platform.self, forKey: .platform)
            self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
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

extension PlatformURL: Comparable {
    public static func < (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue < rhs.platform.rawValue
    }
    
    public static func > (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue > rhs.platform.rawValue
    }
    
    public static func <= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue <= rhs.platform.rawValue
    }
    
    public static func >= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue >= rhs.platform.rawValue
    }
}

public typealias PlatformURLs = [PlatformURL]

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
    
    @NSManaged @objc(version) internal var _version: String
    @NSManaged @objc(versionDate) internal var _versionDate: Date
    @NSManaged @objc(versionDescription) internal var _versionDescription: String?
    
    @NSManaged @objc(downloadURL) internal var _downloadURL: URL
    @NSManaged public private(set) var platformURLs: PlatformURLs?

    @NSManaged public private(set) var tintColor: UIColor?
    @NSManaged public private(set) var isBeta: Bool
    
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
        }
    }
    @NSManaged private var primitiveSourceIdentifier: String?
    
    @NSManaged public var sortIndex: Int32
    
    /* Relationships */
    @NSManaged public var installedApp: InstalledApp?
    @NSManaged public var newsItems: Set<NewsItem>
    
    @NSManaged @objc(source) public var _source: Source?
    @NSManaged @objc(permissions) public var _permissions: NSOrderedSet
    
    @NSManaged public private(set) var latestVersion: AppVersion?
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
    
    @nonobjc public var permissions: [AppPermission] {
        return self._permissions.array as! [AppPermission]
    }
    
    @nonobjc public var versions: [AppVersion] {
        return self._versions.array as! [AppVersion]
    }
    
    @nonobjc public var size: Int64? {
        guard let version = self.latestVersion else { return nil }
        return version.size
    }
    
    @nonobjc public var version: String? {
        guard let version = self.latestVersion else { return nil }
        return version.version
    }
    
    @nonobjc public var versionDescription: String? {
        guard let version = self.latestVersion else { return nil }
        return version.localizedDescription
    }
    
    @nonobjc public var versionDate: Date? {
        guard let version = self.latestVersion else { return nil }
        return version.date
    }
    
    @nonobjc public var downloadURL: URL? {
        guard let version = self.latestVersion else { return nil }
        return version.downloadURL
    }
    
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
        case version
        case versionDescription
        case versionDate
        case iconURL
        case screenshotURLs
        case downloadURL
        case platformURLs
        case tintColor
        case subtitle
        case permissions
        case size
        case isBeta = "beta"
        case versions
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
            self.screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? []
            
            let downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
            let platformURLs = try container.decodeIfPresent(PlatformURLs.self.self, forKey: .platformURLs)
            if let platformURLs = platformURLs {
                self.platformURLs = platformURLs
                // Backwards compatibility, use the fiirst (iOS will be first since sorted that way)
                if let first = platformURLs.sorted().first {
                    self._downloadURL = first.downloadURL
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .platformURLs, in: container, debugDescription: "platformURLs has no entries")

                }
                    
            } else if let downloadURL = downloadURL {
                self._downloadURL = downloadURL
            } else {
                throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "E downloadURL:String or downloadURLs:[[Platform:URL]] key required.")
            }
            
            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                
                self.tintColor = tintColor
            }
            
            self.isBeta = try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false
            
            let permissions = try container.decodeIfPresent([AppPermission].self, forKey: .permissions) ?? []
            self._permissions = NSOrderedSet(array: permissions)
            
            if let versions = try container.decodeIfPresent([AppVersion].self, forKey: .versions)
            {
                //TODO: Throw error if there isn't at least one version.
                
                for version in versions
                {
                    version.appBundleID = self.bundleIdentifier
                }
                
                self.setVersions(versions)
            }
            else
            {
                let version = try container.decode(String.self, forKey: .version)
                let versionDate = try container.decode(Date.self, forKey: .versionDate)
                let versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
                
                let downloadURL = try container.decode(URL.self, forKey: .downloadURL)
                let size = try container.decode(Int32.self, forKey: .size)
                
                let appVersion = AppVersion.makeAppVersion(version: version,
                                                           date: versionDate,
                                                           localizedDescription: versionDescription,
                                                           downloadURL: downloadURL,
                                                           size: Int64(size),
                                                           appBundleID: self.bundleIdentifier,
                                                           in: context)
                self.setVersions([appVersion])
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

private extension StoreApp
{
    func setVersions(_ versions: [AppVersion])
    {
        guard let latestVersion = versions.first else { preconditionFailure("StoreApp must have at least one AppVersion.") }
        
        self.latestVersion = latestVersion
        self._versions = NSOrderedSet(array: versions)
        
        // Preserve backwards compatibility by assigning legacy property values.
        self._version = latestVersion.version
        self._versionDate = latestVersion.date
        self._versionDescription = latestVersion.localizedDescription
        self._downloadURL = latestVersion.downloadURL
        self._size = Int32(latestVersion.size)
    }
}

public extension StoreApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp>
    {
        return NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }
    
    class func makeAltStoreApp(in context: NSManagedObjectContext) -> StoreApp
    {
        let app = StoreApp(context: context)
        app.name = "SideStore"
        
        let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
        if currentAppVersion != nil {
            if currentAppVersion!.contains("beta") {
                app.name += " (Beta)"
            }
            if currentAppVersion!.contains("nightly") {
                app.name += " (Nightly)"
            }
        }
        
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "SideStore Team"
        app.localizedDescription = "SideStore is an alternative app store for non-jailbroken devices.\n\nSideStore allows you to sideload other .ipa files and apps from the Files app or via the SideStore Library."
        app.iconURL = URL(string: "https://sidestore.io/assets/icon.png")!
        app.screenshotURLs = []
        app.sourceIdentifier = Source.altStoreIdentifier
        
        let appVersion = AppVersion.makeAppVersion(version: "0.0.0", // this is set to the current app version later
                                                   date: Date(),
                                                   downloadURL: URL(string: "https://sidestore.io")!,
                                                   size: 0,
                                                   appBundleID: app.bundleIdentifier,
                                                   sourceID: Source.altStoreIdentifier,
                                                   in: context)
        app.setVersions([appVersion])
        
        print("makeAltStoreApp StoreApp: \(String(describing: app))")
        
        return app
    }
}
