//
//  AltWidget.swift
//  AltWidget
//
//  Created by Riley Testut on 6/26/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import WidgetKit
import SwiftUI

import AltStoreCore
import AltSign
import CoreData

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var expirationDate: Date
    var refreshedDate: Date
    
    var tintColor: UIColor?
    var icon: UIImage?
}

struct AppEntry: TimelineEntry
{
    var date: Date
    var relevance: TimelineEntryRelevance?
    
    var app: AppSnapshot?
    var isPlaceholder: Bool = false
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
                        
                        for dayOffset in 0 ..< min(numberOfDays, 7)
                        {
                            guard let entryDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate) else { continue }
                            
                            let score = Float(dayOffset + 1) / Float(numberOfDays)
                            let entry = AppEntry(date: entryDate, relevance: TimelineEntryRelevance(score: score), app: snapshot)
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

struct BackgroundView: View
{
    var icon: UIImage
    var tintColor: UIColor
    
    init(icon: UIImage? = nil, tintColor: UIColor? = nil)
    {
        self.icon = icon ?? UIImage(named: "AltStore")!
        self.tintColor = tintColor ?? .altPrimary
    }

    var body: some View {
        let imageHeight = 60 as CGFloat
        let saturation = 1.8
        let blurRadius = 5 as CGFloat
        let tintOpacity = 0.45
        
        ZStack(alignment: .topTrailing) {
            // Blurred Image
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: /*@START_MENU_TOKEN@*/.fill/*@END_MENU_TOKEN@*/)
                        .frame(width: imageHeight, height: imageHeight, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        .saturation(saturation)
                        .blur(radius: blurRadius, opaque: true)
                        .scaleEffect(geometry.size.width / imageHeight, anchor: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                    
                    Color(tintColor)
                        .opacity(tintOpacity)
                }
            }
            
            Image("Badge")
                .resizable()
                .frame(width: 26, height: 26)
                .padding()
        }
    }
}

struct AltWidgetEntryView : View
{
    var entry: Provider.Entry
    
    var body: some View {
        Group {
            if let app = self.entry.app
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: Date())
                    
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {
                            let imageHeight = geometry.size.height * 0.45
                            
                            app.icon.map {
                                Image(uiImage: $0)
                                    .resizable()
                                    .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                    .frame(height: imageHeight)
                                    .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: /*@START_MENU_TOKEN@*/.continuous/*@END_MENU_TOKEN@*/))
                            }
                                      
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                
                                HStack(alignment: .bottom) {
                                    let text = (
                                        Text("Expires in\n")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color.white.opacity(0.45)) +
                                        
                                        Text(daysRemaining == 1 ? "1 day" : "\(daysRemaining) days")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                    )
                                    
                                    text
                                        .lineLimit(2)
                                        .lineSpacing(1.0)
                                        .minimumScaleFactor(0.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Spacer()
                                    
                                    Countdown(startDate: app.refreshedDate, endDate: app.expirationDate)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .opacity(0.8)
                                        .fixedSize()
                                        .offset(x: 5)
                                        .layoutPriority(100)
                                }
                            }
                            .offset(y: -3)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()
    //                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
    //                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                }
            }
            else if !entry.isPlaceholder
            {
                VStack {
                    Text("App Not Found")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            BackgroundView(icon: entry.app?.icon, tintColor: entry.app?.tintColor)
        )
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
            AltWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("AltWidget")
        .description("View remaining days until your sideloaded apps expire.")
    }
}

struct AltWidget_Previews: PreviewProvider {
    static var previews: some View {
        let refreshedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: refreshedDate) ?? Date()
        
        let altstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              expirationDate: expirationDate,
                              refreshedDate: refreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        let delta = AppSnapshot(name: "Delta",
                              bundleIdentifier: "com.rileytestut.Delta",
                              expirationDate: expirationDate,
                              refreshedDate: refreshedDate,
                              tintColor: .deltaPrimary,
                              icon: UIImage(named: "Delta"))
        
        return Group {
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: altstore))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: delta))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            BackgroundView()
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
