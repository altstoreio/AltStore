//
//  StoreApp10ToStoreApp11Policy.swift
//  AltStoreCore
//
//  Created by Riley Testut on 9/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

// Can't use NSManagedObject subclasses, so add convenience accessors for KVC.
fileprivate extension NSManagedObject
{
    var storeAppBundleID: String? {
        let bundleID = self.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String
        return bundleID
    }
    
    var storeAppSourceID: String? {
        let sourceID = self.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String
        return sourceID
    }
    
    var storeAppVersion: String? {
        let version = self.value(forKey: #keyPath(StoreApp.latestVersionString)) as? String
        return version
    }
    
    var storeAppVersionDate: Date? {
        let versionDate = self.value(forKey: #keyPath(StoreApp._versionDate)) as? Date
        return versionDate
    }
    
    var storeAppVersionDescription: String? {
        let versionDescription = self.value(forKey: #keyPath(StoreApp._versionDescription)) as? String
        return versionDescription
    }
    
    var storeAppSize: NSNumber? {
        let size = self.value(forKey: #keyPath(StoreApp._size)) as? NSNumber
        return size
    }
    
    var storeAppDownloadURL: URL? {
        let downloadURL = self.value(forKey: #keyPath(StoreApp._downloadURL)) as? URL
        return downloadURL
    }
    
    func setStoreAppLatestVersion(_ appVersion: NSManagedObject)
    {
        self.setValue(appVersion, forKey: #keyPath(StoreApp.latestSupportedVersion))
        
        let versions = NSOrderedSet(array: [appVersion])
        self.setValue(versions, forKey: #keyPath(StoreApp._versions))
    }
    
    class func makeAppVersion(version: String,
                              date: Date,
                              localizedDescription: String?,
                              downloadURL: URL,
                              size: Int64,
                              appBundleID: String,
                              sourceID: String,
                              in context: NSManagedObjectContext) -> NSManagedObject
    {
        let appVersion = NSEntityDescription.insertNewObject(forEntityName: AppVersion.entity().name!, into: context)
        appVersion.setValue(version, forKey: #keyPath(AppVersion.version))
        appVersion.setValue(date, forKey: #keyPath(AppVersion.date))
        appVersion.setValue(localizedDescription, forKey: #keyPath(AppVersion.localizedDescription))
        appVersion.setValue(downloadURL, forKey: #keyPath(AppVersion.downloadURL))
        appVersion.setValue(size, forKey: #keyPath(AppVersion.size))
        appVersion.setValue(appBundleID, forKey: #keyPath(AppVersion.appBundleID))
        appVersion.setValue(sourceID, forKey: #keyPath(AppVersion.sourceID))
        return appVersion
    }
}

@objc(StoreApp10ToStoreApp11Policy)
class StoreApp10ToStoreApp11Policy: NSEntityMigrationPolicy
{
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
        
        guard let appBundleID = sInstance.storeAppBundleID,
              let sourceID = sInstance.storeAppSourceID,
              let version = sInstance.storeAppVersion,
              let versionDate = sInstance.storeAppVersionDate,
              // let versionDescription = sInstance.storeAppVersionDescription, // Optional
              let downloadURL = sInstance.storeAppDownloadURL,
              let size = sInstance.storeAppSize as? Int64
        else { return }
        
        guard
            let destinationStoreApp = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first,
            let context = destinationStoreApp.managedObjectContext
        else { fatalError("A destination StoreApp and its managedObjectContext must exist.") }
        
        let appVersion = NSManagedObject.makeAppVersion(
            version: version,
            date: versionDate,
            localizedDescription: sInstance.storeAppVersionDescription,
            downloadURL: downloadURL,
            size: Int64(size),
            appBundleID: appBundleID,
            sourceID: sourceID,
            in: context)
        
        destinationStoreApp.setStoreAppLatestVersion(appVersion)
    }
}
