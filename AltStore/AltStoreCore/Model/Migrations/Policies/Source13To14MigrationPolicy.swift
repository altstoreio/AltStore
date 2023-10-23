//
//  SourceMigrationPolicy.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/19/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import CoreData

fileprivate extension NSManagedObject
{
    var sourceSourceURL: URL? {
        let sourceURL = self.value(forKey: #keyPath(Source.sourceURL)) as? URL
        return sourceURL
    }
    
    var sourceApps: NSOrderedSet? {
        let apps = self.value(forKey: #keyPath(Source._apps)) as? NSOrderedSet
        return apps
    }
    
    var sourceNewsItems: NSOrderedSet? {
        let newsItems = self.value(forKey: #keyPath(Source._newsItems)) as? NSOrderedSet
        return newsItems
    }
}

fileprivate extension NSManagedObject
{
    func setSourceSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(Source.identifier))
    }
    
    func setStoreAppSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(StoreApp.sourceIdentifier))
    }
    
    func setNewsItemSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(NewsItem.sourceIdentifier))
    }
    
    func setAppVersionSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppVersion.sourceID))
    }
    
    func setAppPermissionSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
    }
    
    func setAppScreenshotSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppScreenshot.sourceID))
    }
}

fileprivate extension NSManagedObject
{
    var storeAppVersions: NSOrderedSet? {
        let versions = self.value(forKey: #keyPath(StoreApp._versions)) as? NSOrderedSet
        return versions
    }
    
    var storeAppPermissions: NSSet? {
        let permissions = self.value(forKey: #keyPath(StoreApp._permissions)) as? NSSet
        return permissions
    }
    
    var storeAppScreenshots: NSOrderedSet? {
        let screenshots = self.value(forKey: #keyPath(StoreApp._screenshots)) as? NSOrderedSet
        return screenshots
    }
}

@objc(Source13To14MigrationPolicy)
class Source13To14MigrationPolicy: NSEntityMigrationPolicy
{
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
        
        guard let sourceURL = dInstance.sourceSourceURL else { return }
        
        // Copied from Source.setSourceURL()
        
        let sourceID = try Source.sourceID(from: sourceURL)
        dInstance.setSourceSourceID(sourceID)
        
        for case let newsItem as NSManagedObject in dInstance.sourceNewsItems ?? []
        {
            newsItem.setNewsItemSourceID(sourceID)
        }
        
        for case let app as NSManagedObject in dInstance.sourceApps ?? []
        {
            app.setStoreAppSourceID(sourceID)
            
            // Copied from StoreApp.sourceIdentifier setter
            
            for case let version as NSManagedObject in app.storeAppVersions ?? []
            {
                version.setAppVersionSourceID(sourceID)
            }
            
            for case let permission as NSManagedObject in app.storeAppPermissions ?? []
            {
                permission.setAppPermissionSourceID(sourceID)
            }
            
            for case let screenshot as NSManagedObject in app.storeAppScreenshots ?? []
            {
                screenshot.setAppScreenshotSourceID(sourceID)
            }
        }
    }
}
