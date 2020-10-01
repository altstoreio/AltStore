//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

// Free developer accounts are limited to only 3 active sideloaded apps at a time as of iOS 13.3.1.
public let ALTActiveAppsLimit = 3

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
public class InstalledApp: NSManagedObject, InstalledAppProtocol
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var version: String
    
    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date
    
    @NSManaged public var isActive: Bool
    @NSManaged public var needsResign: Bool
    @NSManaged public var hasAlternateIcon: Bool
    
    @NSManaged public var certificateSerialNumber: String?
    
    /* Transient */
    @NSManaged public var isRefreshing: Bool
    
    /* Relationships */
    @NSManaged public var storeApp: StoreApp?
    @NSManaged public var team: Team?
    @NSManaged public var appExtensions: Set<InstalledExtension>
    
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
    
    public init(resignedApp: ALTApplication, originalBundleIdentifier: String, certificateSerialNumber: String?, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        
        self.update(resignedApp: resignedApp, certificateSerialNumber: certificateSerialNumber)
    }
    
    public func update(resignedApp: ALTApplication, certificateSerialNumber: String?)
    {
        self.name = resignedApp.name
        
        self.resignedBundleIdentifier = resignedApp.bundleIdentifier
        self.version = resignedApp.version
        
        self.certificateSerialNumber = certificateSerialNumber

        if let provisioningProfile = resignedApp.provisioningProfile
        {
            self.update(provisioningProfile: provisioningProfile)
        }
    }
    
    public func update(provisioningProfile: ALTProvisioningProfile)
    {
        self.refreshedDate = provisioningProfile.creationDate
        self.expirationDate = provisioningProfile.expirationDate
    }
    
    public func loadIcon(completion: @escaping (Result<UIImage?, Error>) -> Void)
    {
        let hasAlternateIcon = self.hasAlternateIcon
        let alternateIconURL = self.alternateIconURL
        let fileURL = self.fileURL
        
        DispatchQueue.global().async {
            do
            {
                if hasAlternateIcon,
                   case let data = try Data(contentsOf: alternateIconURL),
                   let icon = UIImage(data: data)
                {
                    return completion(.success(icon))
                }
                
                let application = ALTApplication(fileURL: fileURL)
                completion(.success(application?.icon))
            }
            catch
            {
                completion(.failure(error))
            }
        }
    }
}

public extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
    
    class func updatesFetchRequest() -> NSFetchRequest<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K == YES AND %K != nil AND %K != %K",
                                             #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.version), #keyPath(InstalledApp.storeApp.version))
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
        var predicate = NSPredicate(format: "%K == YES AND %K != %@", #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
        {
            // No additional predicate
        }
        else
        {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
        }
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context)
        {
            // Refresh AltStore last since it causes app to quit.
            installedApps.append(altStoreApp)
        }
        
        return installedApps
    }
    
    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        // Date 6 hours before now.
        let date = Date().addingTimeInterval(-1 * 6 * 60 * 60)
        
        var predicate = NSPredicate(format: "(%K == YES) AND (%K < %@) AND (%K != %@)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        if let patreonAccount = DatabaseManager.shared.patreonAccount(in: context), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
        {
            // No additional predicate
        }
        else
        {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate,
                                                                            NSPredicate(format: "%K == nil OR %K == NO", #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.isBeta))])
        }
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context), altStoreApp.refreshedDate < date
        {
            // Refresh AltStore last since it may cause app to quit.
            installedApps.append(altStoreApp)
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
