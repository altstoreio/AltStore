//
//  HomeScreenWidget.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit
import CoreData

import AltStoreCore
import AltSign

private extension Color
{
    static let altGradientLight = Color.init(.displayP3, red: 123.0/255.0, green: 200.0/255.0, blue: 176.0/255.0)
    static let altGradientDark = Color.init(.displayP3, red: 0.0/255.0, green: 128.0/255.0, blue: 132.0/255.0)
    
    static let altGradientExtraDark = Color.init(.displayP3, red: 2.0/255.0, green: 82.0/255.0, blue: 103.0/255.0)
}

@available(iOS 17, *)
struct ActiveAppsWidget: Widget
{
    private let kind: String = "ActiveApps"
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AppsTimelineProvider()) { entry in
            ActiveAppsWidgetView(entry: entry)
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("AltWidget")
        .description("View remaining days until your active apps expire.")
    }
}

@available(iOS 17, *)
private struct ActiveAppsWidgetView: View
{
    var entry: AppsEntry
    
    @Environment(\.colorScheme)
    private var colorScheme
    
    var body: some View {
        Group {
            if entry.apps.isEmpty
            {
                placeholder
            }
            else
            {
                content
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            if colorScheme == .dark
            {
                LinearGradient(colors: [.altGradientDark, .altGradientExtraDark], startPoint: .top, endPoint: .bottom)
            }
            else
            {
                LinearGradient(colors: [.altGradientLight, .altGradientDark], startPoint: .top, endPoint: .bottom)
            }
        }
    }
    
    private var content: some View {
        GeometryReader { (geometry) in
            
            let numberOfApps = max(entry.apps.count, 1) // Ensure we don't divide by 0
            let preferredRowHeight = (geometry.size.height / Double(numberOfApps)) - 8
            let rowHeight = min(preferredRowHeight, geometry.size.height / 2)
            
            ZStack(alignment: .center) {
                VStack(spacing: 12) {
                    ForEach(entry.apps, id: \.bundleIdentifier) { app in
                        
                        let daysRemaining = app.expirationDate.numberOfCalendarDays(since: entry.date)
                        let cornerRadius = rowHeight / 5.0
                        
                        HStack(spacing: 10) {
                            Image(uiImage: app.icon ?? UIImage(named: "AltStore")!)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(cornerRadius)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                
                                let text = if entry.date > app.expirationDate
                                {
                                    Text("Expired")
                                }
                                else
                                {
                                    Text("Expires in \(daysRemaining) ") + (daysRemaining == 1 ? Text("day") : Text("days"))
                                }
                                
                                text
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack {
                                Spacer()
                                
                                Countdown(startDate: app.refreshedDate, 
                                          endDate: app.expirationDate,
                                          currentDate: entry.date,
                                          strokeWidth: 3.0) // Slightly thinner circle stroke width
                                .background {
                                    Color.black.opacity(0.1)
                                        .mask(Capsule())
                                        .padding(.all, -5)
                                }
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .invalidatableContent()
                            }
                            .activatesRefreshAllAppsIntent()
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var placeholder: some View {
        Text("App Not Found")
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(Color.white.opacity(0.4))
    }
}

#Preview(as: .systemMedium) {
    guard #available(iOS 17, *) else { fatalError() }
    return ActiveAppsWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, delta, clip, longAltStore, longDelta, longClip) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry(date: Date(), apps: [altstore, delta, clip])
    AppsEntry(date: Date(), apps: [longAltStore, longDelta, longClip])
    
    AppsEntry(date: expiredDate, apps: [altstore, delta, clip])
    
    AppsEntry(date: Date(), apps: [altstore, delta])
    AppsEntry(date: Date(), apps: [altstore])
    
    AppsEntry(date: Date(), apps: [])
    AppsEntry(date: Date(), apps: [], isPlaceholder: true)
}
