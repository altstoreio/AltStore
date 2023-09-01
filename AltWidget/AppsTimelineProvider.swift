//
//  AppsTimelineProvider.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import WidgetKit
import CoreData

import AltStoreCore

struct AppsEntry: TimelineEntry
{
    var date: Date
    var relevance: TimelineEntryRelevance?
    
    var apps: [AppSnapshot]
    var isPlaceholder: Bool = false
}

struct AppsTimelineProvider
{
    typealias Entry = AppsEntry
    
    func placeholder(in context: TimelineProviderContext) -> AppsEntry
    {
        return AppsEntry(date: Date(), apps: [], isPlaceholder: true)
    }
    
    func snapshot(for appBundleIDs: [String]) async -> AppsEntry
    {
        do
        {
            try await self.prepare()
            
            let apps = try await self.fetchApps(withBundleIDs: appBundleIDs)
            
            let entry = AppsEntry(date: Date(), apps: apps)
            return entry
        }
        catch
        {
            print("Failed to prepare widget snapshot:", error)
            
            let entry = AppsEntry(date: Date(), apps: [])
            return entry
        }
    }
    
    func timeline(for appBundleIDs: [String]) async -> Timeline<AppsEntry>
    {
        do
        {
            try await self.prepare()
            
            let apps = try await self.fetchApps(withBundleIDs: appBundleIDs)
            
            let entries = self.makeEntries(for: apps)
            let timeline = Timeline(entries: entries, policy: .atEnd)
            return timeline
        }
        catch
        {
            print("Failed to prepare widget timeline:", error)
            
            let entry = AppsEntry(date: Date(), apps: [])
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            return timeline
        }
    }
}

private extension AppsTimelineProvider
{
    func prepare() async throws
    {
        try await DatabaseManager.shared.start()
    }
    
    func fetchApps(withBundleIDs bundleIDs: [String]) async throws -> [AppSnapshot]
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let apps = try await context.performAsync {
            let fetchRequest = InstalledApp.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%K IN %@", #keyPath(InstalledApp.bundleIdentifier), bundleIDs)
            fetchRequest.returnsObjectsAsFaults = false
            
            let installedApps = try context.fetch(fetchRequest)
            
            let apps = installedApps.map { AppSnapshot(installedApp: $0) }
            
            // Always list apps in alphabetical order.
            let sortedApps = apps.sorted { $0.name < $1.name }
            return sortedApps
        }
        
        return apps
    }
    
    func makeEntries(for snapshots: [AppSnapshot]) -> [AppsEntry]
    {
        let sortedAppsByExpirationDate = snapshots.sorted { $0.expirationDate < $1.expirationDate }
        guard let firstExpiringApp = sortedAppsByExpirationDate.first, let lastExpiringApp = sortedAppsByExpirationDate.last else { return [] }
        
        let currentDate = Calendar.current.startOfDay(for: Date())
        let numberOfDays = lastExpiringApp.expirationDate.numberOfCalendarDays(since: currentDate)
        
        // Generate a timeline consisting of one entry per day.
        var entries: [AppsEntry] = []
        
        switch numberOfDays
        {
        case ..<0:
            let entry = AppsEntry(date: currentDate, relevance: TimelineEntryRelevance(score: 0.0), apps: snapshots)
            entries.append(entry)
            
        case 0:
            let entry = AppsEntry(date: currentDate, relevance: TimelineEntryRelevance(score: 1.0), apps: snapshots)
            entries.append(entry)
            
        default:
            // To reduce memory consumption, we only generate entries for the next week. This includes:
            // * 1 for each day the "least expired" app is valid (up to 7)
            // * 1 "0 days remaining"
            // * 1 "Expired"
            
            let numberOfEntries = min(numberOfDays, 7) + 2
            
            let appEntries = (0 ..< numberOfEntries).map { (dayOffset) -> AppsEntry in
                let entryDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate) ?? currentDate.addingTimeInterval(Double(dayOffset) * 60 * 60 * 24)
                                
                let daysSinceRefresh = entryDate.numberOfCalendarDays(since: firstExpiringApp.refreshedDate)
                let totalNumberOfDays = firstExpiringApp.expirationDate.numberOfCalendarDays(since: firstExpiringApp.refreshedDate)
                
                var score = (entryDate <= firstExpiringApp.expirationDate) ? Float(daysSinceRefresh + 1) / Float(totalNumberOfDays + 1) : 1 // Expired apps have a score of 1.
                if snapshots.allSatisfy({ $0.expirationDate > currentDate })
                {
                    // Unless ALL apps are expired, in which case relevance is 0.
                    score = 0
                }
                
                let entry = AppsEntry(date: entryDate, relevance: TimelineEntryRelevance(score: score), apps: snapshots)
                return entry
            }
            
            entries.append(contentsOf: appEntries)
        }
        
        return entries
    }
}

extension AppsTimelineProvider: TimelineProvider
{
    func getSnapshot(in context: Context, completion: @escaping (AppsEntry) -> Void)
    {
        Task<Void, Never> {
            let bundleIDs = await self.fetchActiveAppBundleIDs()
            
            let snapshot = await self.snapshot(for: bundleIDs)
            completion(snapshot)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<AppsEntry>) -> Void)
    {
        Task<Void, Never> {
            let bundleIDs = await self.fetchActiveAppBundleIDs()
            
            let timeline = await self.timeline(for: bundleIDs)
            completion(timeline)
        }
    }
    
    private func fetchActiveAppBundleIDs() async -> [String]
    {
        do
        {
            try await self.prepare()
            
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let bundleIDs = try await context.performAsync {
                let fetchRequest = InstalledApp.activeAppsFetchRequest() as! NSFetchRequest<NSDictionary>
                fetchRequest.resultType = .dictionaryResultType
                fetchRequest.propertiesToFetch = [#keyPath(InstalledApp.bundleIdentifier)]
                
                let bundleIDs = try context.fetch(fetchRequest).compactMap { $0[#keyPath(InstalledApp.bundleIdentifier)] as? String }
                return bundleIDs
            }
            
            return bundleIDs
        }
        catch
        {
            print("Failed to fetch active bundle IDs, falling back to AltStore bundle ID.", error)
            
            return [StoreApp.altstoreAppID]
        }
    }
}
