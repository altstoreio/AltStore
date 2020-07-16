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
    
    lazy var darkenedIcon: UIImage? = {
        let color = (self.tintColor ?? UIColor.altstorePrimary).withAlphaComponent(0.35)
        let darkenedIcon = self.icon?.applyBlur(withRadius: 20, tintColor: color, saturationDeltaFactor: 1.8, maskImage: nil)
        return darkenedIcon
    }()
}

extension AppSnapshot
{
    // Declared in extension so we retain synthesized initializer.
    init(installedApp: InstalledApp)
    {
        self.name = installedApp.name
        self.bundleIdentifier = installedApp.bundleIdentifier
        self.expirationDate = installedApp.expirationDate
        
        self.tintColor = installedApp.storeApp?.tintColor
        
//        let application = ALTApplication(fileURL: installedApp.fileURL)
        self.icon = UIImage(named: installedApp.name)// application?.icon
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
            do
            {
                let context = try result.get()
                                
                let snapshot = configuration.app?.identifier.map { (identifier) in
                    InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), identifier),
                                       in: context).map(AppSnapshot.init)
                } ?? nil
                
                var entries: [AppEntry] = []

                // Generate a timeline consisting of five entries an hour apart, starting from the current date.
                let currentDate = Date()
                for hourOffset in 0 ..< 5 {
                    let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
                    let entry = AppEntry(date: entryDate, app: snapshot)
                    entries.append(entry)
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
    var app: AppSnapshot?
}

struct PlaceholderView : View {
    var body: some View {
        Text("Placeholder 2")
    }
}

struct AltWidgetEntryView : View {
    var entry: Provider.Entry
    
    @ViewBuilder
    var body: some View {
        if var app = self.entry.app
        {
            let daysRemaining = app.expirationDate.numberOfCalendarDays(since: Date())
                
            GeometryReader { (geometry) in
                Group {
                    VStack(alignment: .leading) {
                        HStack(alignment: .top) {
                            
                            let imageHeight = geometry.size.height * 0.45
                            
                            Image(app.name)
                                .resizable()
                                .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                .frame(height: imageHeight)
                                .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: /*@START_MENU_TOKEN@*/.continuous/*@END_MENU_TOKEN@*/))
                            
                            Spacer()
                            
                            Image("Badge")
                                .resizable()
                                .frame(width: 26, height: 26)
                        }
                                  
                        Spacer()
                        
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading) {
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)

                                Spacer(minLength: 2)

                                VStack(alignment: .leading, spacing: 0) {
                                    (
                                        Text("Expires in\n")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.white.opacity(0.35)) +
                                        Text(daysRemaining == 1 ? "1 day" : "\(daysRemaining) days")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                                    .lineSpacing(1.0)
                                    .minimumScaleFactor(0.5)
                                }
                            }

                            Spacer()

                            Countdown(numberOfDays: daysRemaining)
                                .font(.system(size: 20, weight: .semibold))
                                .offset(x: 6.5, y: 5)
                                .padding(.leading, -6.5)
                                .padding(.top, -5)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                .background(
                    ZStack {
                        app.darkenedIcon.map {
                            Image(uiImage: $0)
                                .resizable()
                        }
                    }
                )
//                .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
//                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            }
        }
        else{
            Text("No App")
        }
    }
}

@main
struct AltWidget: Widget
{
    private let kind: String = "AltWidget"

    public var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ViewAppIntent.self, provider: Provider(), placeholder: PlaceholderView()) { (entry) in
            AltWidgetEntryView(entry: entry)
        }
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
        }
    }
}
