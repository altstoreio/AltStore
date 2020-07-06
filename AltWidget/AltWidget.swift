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
                
                let entry = AppEntry(date: Date(), installedApp: installedApp)
                completion(entry)
            }
            catch
            {
                print("Error:", error)
                
                let entry = AppEntry(date: Date(), installedApp: nil)
                completion(entry)
            }
        }
        
//        let entry = AppEntry(date: Date())
//        completion(entry)
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
                    let entry = AppEntry(date: entryDate, installedApp: installedApp)
                    entries.append(entry)
                }

                let timeline = Timeline(entries: entries, policy: .atEnd)
                completion(timeline)
            }
            catch
            {
                print("Error:", error)
                
                let entry = AppEntry(date: Date(), installedApp: nil)
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
    
    public var installedApp: InstalledApp?
    public var app: AppSnapshot?
}

struct PlaceholderView : View {
    var body: some View {
        Text("Placeholder View")
    }
}

struct AltWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        GeometryReader { (geometry) in
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Image("AltStore")
                        .resizable()
                        .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                        .mask(ContainerRelativeShape())
                        .shadow(radius: /*@START_MENU_TOKEN@*/10/*@END_MENU_TOKEN@*/)
                    
                    Spacer()
                    
                    Image("AltStore")
                        .resizable()
                        .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                        .frame(height: geometry.size.height / 4)
                        .mask(ContainerRelativeShape())
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("AltStore")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .bold()
                        
                        Spacer()
                        
                        Text("Expires in")
                            .font(.caption2)
                            .layoutPriority(100)
                    }
                    
                    Text("7 DAYS")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.vertical, 6)
                        .frame(minWidth: nil, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                        .background(Color.green)
                        .mask(Capsule())
                }
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 11, trailing: 16))
            .foregroundColor(.white)
        }
        .background(
            Image("AppIconBackground")
                .resizable()
        )
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
        
        let app = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              resignedBundleIdentifier: "com.rileytestut.AltStore.resigned",
                              version: "1.4",
                              refreshedDate: Date(),
                              expirationDate: expirationDate,
                              installedDate: refreshedDate)
        return Group {
            AltWidgetEntryView(entry: AppEntry(date: Date(), app: app))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
