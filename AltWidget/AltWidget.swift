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
import CoreData

extension UIColor
{
    static let altstorePrimary = UIColor(named: "Primary")!
    static let deltaPrimary = UIColor(named: "DeltaPrimary")!
}

extension Color
{
    static let altstorePrimary = Color("Primary")
    static let deltaPrimary = Color("DeltaPrimary")
}

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var expirationDate: Date
    
    var tintColor: UIColor?
    var icon: UIImage?
//
//    lazy var darkenedIcon: UIImage? = {
//        guard let icon = self.icon else { return nil }
//
//        let color = (self.tintColor ?? UIColor.altstorePrimary).withAlphaComponent(0.55)
//
//        let resizedImage = icon.resizing(toFit: CGSize(width: 180, height: 180))
//        let darkenedIcon = resizedImage?.applyBlur(withRadius: 15, tintColor: color, saturationDeltaFactor: 1.8, maskImage: nil)
//        return darkenedIcon
//    }()
}

extension AppSnapshot
{
    // Declared in extension so we retain synthesized initializer.
    init(installedApp: InstalledApp)
    {
        let socket = ALTDeviceListeningSocket
        self.name = installedApp.name
        self.bundleIdentifier = installedApp.bundleIdentifier
        self.expirationDate = installedApp.expirationDate
        
        self.tintColor = installedApp.storeApp?.tintColor
        
        let application = ALTApplication(fileURL: installedApp.fileURL)
        self.icon = application?.icon?.resizing(toFill: CGSize(width: 180, height: 180))
    }
}

struct Provider: IntentTimelineProvider
{
    typealias Entry = AppEntry
    
    func snapshot(for configuration: ViewAppIntent, with context: Context, completion: @escaping (AppEntry) -> ())
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

    func timeline(for configuration: ViewAppIntent, with context: Context, completion: @escaping (Timeline<Entry>) -> ())
    {
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
                        installedApp = app ?? InstalledApp.fetchAltStore(in: context)
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
                        
                        for dayOffset in 0 ..< max(numberOfDays, 7)
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

struct AppEntry: TimelineEntry
{
    var date: Date
    var relevance: TimelineEntryRelevance?
    
    var app: AppSnapshot?
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
                            
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading) {
                                    Text(app.name.uppercased())
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)

                                    Spacer(minLength: 2)

                                    VStack(alignment: .leading, spacing: 0) {
                                        (
                                            Text("Expires in\n")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(Color.white.opacity(0.45)) +
                                            Text(daysRemaining == 1 ? "1 day" : "\(daysRemaining) days")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                        )
                                        .lineSpacing(1.0)
                                        .minimumScaleFactor(0.5)
                                    }
                                }

                                Spacer()

                                Countdown(numberOfDays: daysRemaining)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.8))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()
    //                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
    //                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                }
            }
            else
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
    private let kind: String = "AltWidget"

    public var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ViewAppIntent.self, provider: Provider(), placeholder: BackgroundView()) { (entry) in
            AltWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("AltWidget")
        .description("View remaining days until your sideloaded apps expire.")
    }
}

struct AltWidget_Previews: PreviewProvider {
    static var previews: some View {
        let refreshedDate = Date()
        let expirationDate = refreshedDate.addingTimeInterval(1 * 7 * 24 * 60 * 60)
        
        let altstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              expirationDate: expirationDate,
                              tintColor: .altstorePrimary,
                              icon: UIImage(named: "AltStore"))
        
        let delta = AppSnapshot(name: "Delta",
                              bundleIdentifier: "com.rileytestut.Delta",
                              expirationDate: expirationDate,
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
