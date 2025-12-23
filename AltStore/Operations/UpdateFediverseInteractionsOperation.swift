//
//  UpdateFediverseInteractionsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 11/21/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore

class UpdateFediverseInteractionsOperation: ResultOperation<Void>, @unchecked Sendable
{
    override init()
    {
        super.init()
    }
    
    override func main()
    {
        super.main()

        Task<Void, Never>(priority: .userInitiated) {
            do
            {
                try await self.updateRecentNewsItems()
                try await self.updateAvailableAppUpdates()
                try await self.updateFirstAppForSources()
                
                self.finish(.success(()))
            }
            catch
            {                
                self.finish(.failure(error))
            }
        }
    }
}

private extension UpdateFediverseInteractionsOperation
{
    func updateRecentNewsItems() async throws
    {
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            let (recentNewsItems, statusIDs) = await context.perform {
                let fetchRequest = NewsItem.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K != nil", #keyPath(NewsItem.federatedURL))
                fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \NewsItem.date, ascending: false)]
                fetchRequest.fetchLimit = 5
                
                let recentNewsItems = NewsItem.fetch(fetchRequest, in: context)
                let statusIDs = recentNewsItems.compactMap { $0.statusID }
                return (recentNewsItems, Set(statusIDs))
            }
            
            let toots = try await MastodonAPI.shared.fetchToots(ids: statusIDs)
            let tootsByID = toots.reduce(into: [:]) { $0[$1.id] = $1 }
            
            try context.performAndWait {
                for newsItem in recentNewsItems
                {
                    guard let statusID = newsItem.statusID, let toot = tootsByID[statusID] else { continue }
                    newsItem.federatedURL = toot.url
                    newsItem.likesCount = Int32(toot.favourites_count)
                    newsItem.boostsCount = Int32(toot.reblogs_count)
                    newsItem.commentsCount = Int32(toot.replies_count)
                }
                
                try context.save()
            }
        }
        catch
        {
            Logger.main.error("Failed to fetch Fediverse interactions for recent News items. \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func updateAvailableAppUpdates() async throws
    {
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let (appVersions, statusIDs) = await context.perform {
                let fetchRequest = InstalledApp.supportedUpdatesFetchRequest()
                fetchRequest.fetchLimit = MyAppsViewController.maximumCollapsedUpdatesCount
                
                let installedApps = InstalledApp.fetch(fetchRequest, in: context)
                let appVersions = installedApps.compactMap { $0.storeApp?.latestSupportedVersion }
                
                let statusIDs = appVersions.compactMap { $0.statusID }
                return (appVersions, Set(statusIDs))
            }
            
            let toots = try await MastodonAPI.shared.fetchToots(ids: statusIDs)
            let tootsByID = toots.reduce(into: [:]) { $0[$1.id] = $1 }
            
            try context.performAndWait {
                for appVersion in appVersions
                {
                    guard let statusID = appVersion.statusID, let toot = tootsByID[statusID] else { continue }
                    appVersion.federatedURL = toot.url
                    appVersion.likesCount = Int32(toot.favourites_count)
                    appVersion.boostsCount = Int32(toot.reblogs_count)
                    appVersion.commentsCount = Int32(toot.replies_count)
                }
                                
                try context.save()
            }
        }
        catch
        {
            Logger.main.error("Failed to fetch Fediverse interactions for available updates. \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func updateFirstAppForSources() async throws
    {
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            let (storeApps, statusIDs) = try await context.perform {
                let fetchRequest = StoreApp.browseTabFeaturedAppsFetchRequest()
                
                let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: #keyPath(StoreApp._source.featuredSortID), cacheName: nil)
                try fetchedResultsController.performFetch()
                
                var storeApps: [StoreApp] = []
                for section in fetchedResultsController.sections ?? []
                {
                    let apps = section.objects as! [StoreApp]
                    
                    if let storeApp = apps.first
                    {
                        // Only fetch interactions for the first app in each section.
                        storeApps.append(storeApp)
                    }
                }
                
                let statusIDs = storeApps.compactMap { $0.statusID }
                return (storeApps, Set(statusIDs))
            }
            
            let toots = try await MastodonAPI.shared.fetchToots(ids: statusIDs)
            let tootsByID = toots.reduce(into: [:]) { $0[$1.id] = $1 }
            
            try context.performAndWait {
                for storeApp in storeApps
                {
                    guard let statusID = storeApp.statusID, let toot = tootsByID[statusID] else { continue }
                    storeApp.federatedURL = toot.url
                    storeApp.likesCount = Int32(toot.favourites_count)
                    storeApp.boostsCount = Int32(toot.reblogs_count)
                    storeApp.commentsCount = Int32(toot.replies_count)
                }
                                
                try context.save()
            }
        }
        catch
        {
            Logger.main.error("Failed to fetch Fediverse interactions for first apps in sources. \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
