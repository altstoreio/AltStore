//
//  AltWidget.swift
//  AltWidget
//
//  Created by Riley Testut on 6/26/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit
import UIKit
import CoreData

import AltStoreCore
import AltSign

struct AppEntry: TimelineEntry
{
    var date: Date
    var relevance: TimelineEntryRelevance?
    
    var app: AppSnapshot?
    var isPlaceholder: Bool = false
}

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var expirationDate: Date
    var refreshedDate: Date
    
    var tintColor: UIColor?
    var icon: UIImage?
}

extension AppSnapshot
{
    // Declared in extension so we retain synthesized initializer.
    init(installedApp: InstalledApp)
    {
        self.name = installedApp.name
        self.bundleIdentifier = installedApp.bundleIdentifier
        self.expirationDate = installedApp.expirationDate
        self.refreshedDate = installedApp.refreshedDate
        
        self.tintColor = installedApp.storeApp?.tintColor
        
        let application = ALTApplication(fileURL: installedApp.fileURL)
        self.icon = application?.icon?.resizing(toFill: CGSize(width: 180, height: 180))
    }
}

struct Provider: IntentTimelineProvider
{
    typealias Intent = ViewAppIntent
    typealias Entry = AppEntry
    
    func placeholder(in context: Context) -> AppEntry
    {
        return AppEntry(date: Date(), app: nil, isPlaceholder: true)
    }
    
    func getSnapshot(for configuration: ViewAppIntent, in context: Context, completion: @escaping (AppEntry) -> Void)
    {
        self.prepare { (result) in
            do
            {
                let context = try result.get()
                let snapshot = InstalledApp.fetchAltStore(in: context).map(AppSnapshot.init)

                let entry = AppEntry(date: Date(), app: snapshot)
                completion(entry)
            }
            catch
            {
                print("Error preparing widget snapshot:", error)
                
                let entry = AppEntry(date: Date(), app: nil)
                completion(entry)
            }
        }
    }
    
    func getTimeline(for configuration: ViewAppIntent, in context: Context, completion: @escaping (Timeline<AppEntry>) -> Void) {
        self.prepare { (result) in
            autoreleasepool {
                do
                {
                    let context = try result.get()
                    
                    let installedApp: InstalledApp?
                    
                    if let identifier = configuration.app?.identifier
                    {
                        let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), identifier),
                                                     in: context)
                        installedApp = app
                    }
                    else
                    {
                        installedApp = InstalledApp.fetchAltStore(in: context)
                    }
                    
                    let snapshot = installedApp.map(AppSnapshot.init)
                    
                    var entries: [AppEntry] = []

                    // Generate a timeline consisting of one entry per day.
                                    
                    if let snapshot = snapshot
                    {
                        let currentDate = Calendar.current.startOfDay(for: Date())
                        let numberOfDays = snapshot.expirationDate.numberOfCalendarDays(since: currentDate)
                        
                        if numberOfDays >= 0
                        {
                            for dayOffset in 0 ..< min(numberOfDays, 7)
                            {
                                guard let entryDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate) else { continue }
                                
                                let score = Float(dayOffset + 1) / Float(numberOfDays)
                                let entry = AppEntry(date: entryDate, relevance: TimelineEntryRelevance(score: score), app: snapshot)
                                entries.append(entry)
                            }
                        }
                        else
                        {
                            let entry = AppEntry(date: Date(), app: snapshot)
                            entries.append(entry)
                        }
                    }

                    let timeline = Timeline(entries: entries, policy: .atEnd)
                    completion(timeline)
                }
                catch
                {
                    print("Error preparing widget timeline:", error)
                    
                    let entry = AppEntry(date: Date(), app: nil)
                    let timeline = Timeline(entries: [entry], policy: .atEnd)
                    completion(timeline)
                }
            }
        }
    }
    
    private func prepare(completion: @escaping (Result<NSManagedObjectContext, Error>) -> Void)
    {
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                completion(.failure(error))
            }
            else
            {
                DatabaseManager.shared.viewContext.perform {
                    completion(.success(DatabaseManager.shared.viewContext))
                }
            }
        }
    }
}

@main
struct AltWidget: Widget
{
    private let kind: String = "AppDetail"
    
    public var body: some WidgetConfiguration {
        return IntentConfiguration(kind: kind,
                                   intent: ViewAppIntent.self,
                                   provider: Provider()) { (entry) in
            WidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("AltWidget")
        .description("View remaining days until your sideloaded apps expire.")
    }
}
