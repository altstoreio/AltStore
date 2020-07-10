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

extension Color
{
    static let altstorePrimary = Color("Primary")
    static let deltaPrimary = Color("DeltaPrimary")
}

@propertyWrapper
struct RSTManaged<Value: NSManagedObject>
{
    private var managedObject: Value?
    private var managedObjectContext: NSManagedObjectContext?
    
    var wrappedValue: Value? {
        get { self.managedObject }
        set {
            self.managedObject = newValue
            self.managedObjectContext = newValue?.managedObjectContext
        }
    }
}

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var resignedBundleIdentifier: String
    var version: String
    
    var refreshedDate: Date
    var expirationDate: Date
    var installedDate: Date
    
    var tintColor: Color
}

extension AppSnapshot
{
    // Declared in extension so we retain synthesized initializer.
    init(installedApp: InstalledApp)
    {
        self.name = installedApp.name
        self.bundleIdentifier = installedApp.bundleIdentifier
        self.resignedBundleIdentifier = installedApp.resignedBundleIdentifier
        self.version = installedApp.version
        self.refreshedDate = installedApp.refreshedDate
        self.expirationDate = installedApp.expirationDate
        self.installedDate = installedApp.installedDate
        
        if let tintColor = installedApp.storeApp?.tintColor
        {
            self.tintColor = Color(tintColor)
        }
        else
        {
            self.tintColor = .altstorePrimary
        }
    }
}

struct Provider: TimelineProvider
{
    public typealias Entry = AppEntry

    public func snapshot(with context: Context, completion: @escaping (AppEntry) -> ())
    {
        self.prepare { (result) in
            do
            {
                let context = try result.get()
                
                let installedApp = InstalledApp.fetchAltStore(in: context)
                let snapshot = installedApp.map { AppSnapshot(installedApp: $0) }
                
                let entry = AppEntry(date: Date(), app: snapshot)
                completion(entry)
            }
            catch
            {
                print("Error:", error)
                
                let entry = AppEntry(date: Date(), app: nil)
                completion(entry)
            }
        }
    }

    public func timeline(with context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        self.prepare { (result) in
            do
            {
                let context = try result.get()
                
                let installedApp = InstalledApp.fetchAltStore(in: context)
                
                var entries: [AppEntry] = []

                // Generate a timeline consisting of five entries an hour apart, starting from the current date.
                let currentDate = Date()
                for hourOffset in 0 ..< 5 {
                    let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
                    let entry = AppEntry(date: entryDate, app: installedApp.map(AppSnapshot.init))
                    entries.append(entry)
                }

                let timeline = Timeline(entries: entries, policy: .atEnd)
                completion(timeline)
            }
            catch
            {
                print("Error:", error)
                
                let entry = AppEntry(date: Date(), app: nil)
                let timeline = Timeline(entries: [entry], policy: .atEnd)
                completion(timeline)
            }
        }
    }
    
    private func prepare(completion: @escaping (Result<NSManagedObjectContext, Error>) -> Void)
    {
        func finish(_ result: Result<Void, Error>)
        {
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success:
                DatabaseManager.shared.viewContext.perform {
                    completion(.success(DatabaseManager.shared.viewContext))
                }
            }
        }
        
        guard !DatabaseManager.shared.isStarted else { return finish(.success(())) }
        
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                finish(.failure(error))
            }
            else
            {
                finish(.success(()))
            }
        }
    }
}

struct AppEntry: TimelineEntry
{
    public var date: Date
    
    public var app: AppSnapshot?
}

struct PlaceholderView : View {
    var body: some View {
        Text("Placeholder View")
    }
}

struct AltWidgetEntryView : View {
    var entry: Provider.Entry
    
    var darkenedImage: UIImage {
        let color = UIColor(white: 0.0, alpha: 0.4)
        let image = self.entry.app.map {
            UIImage(named: $0.name)?.applyBlur(withRadius: 10, tintColor: color, saturationDeltaFactor: 1.8, maskImage: nil)
        } ?? nil
        return image!
    }
    
    @ViewBuilder
    var body: some View {
        if let app = self.entry.app
        {
            GeometryReader { (geometry) in
                Group {
                    VStack(alignment: .leading) {
                        HStack(alignment: .top) {
                            Image(app.name)
                                .resizable()
                                .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                .frame(height: geometry.size.height * 0.45)
                                .mask(ContainerRelativeShape())
                            
                            Spacer()
                            
                            Image("Badge")
                                .resizable()
                                .frame(width: 26, height: 26)
                        }
                                  
                        Spacer()
                        
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading) {
                                Text(app.name.uppercased())
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)

                                Spacer(minLength: 2)

                                VStack(alignment: .leading, spacing: 0) {
                                    (
                                        Text("Expires in\n")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.white.opacity(0.35)) +
                                        Text("7 days")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                                    .lineSpacing(1.0)
                                    .layoutPriority(10)
                                    .minimumScaleFactor(0.5)
                                }
                            }

                            Spacer()

                            Countdown(numberOfDays: 7)
                                .font(.system(size: 20, weight: .semibold))
                                .offset(x: 6.5, y: 5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                .background(
                    ZStack {
                        app.tintColor
                        Color.black.opacity(0.25)
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
        StaticConfiguration(kind: kind, provider: Provider(), placeholder: PlaceholderView()) { entry in
            AltWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}

struct AltWidget_Previews: PreviewProvider {
    static var previews: some View {
        let refreshedDate = Date()
        let expirationDate = refreshedDate.addingTimeInterval(1 * 7 * 24 * 60 * 60)
        
        let altstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              resignedBundleIdentifier: "com.rileytestut.AltStore.resigned",
                              version: "1.4",
                              refreshedDate: Date(),
                              expirationDate: expirationDate,
                              installedDate: refreshedDate,
                              tintColor: .altstorePrimary)
        
        let delta = AppSnapshot(name: "Delta",
                              bundleIdentifier: "com.rileytestut.Delta",
                              resignedBundleIdentifier: "com.rileytestut.Delta.resigned",
                              version: "1.4",
                              refreshedDate: Date(),
                              expirationDate: expirationDate,
                              installedDate: refreshedDate,
                              tintColor: .deltaPrimary)
        
        return Group {
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: altstore))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: delta))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
