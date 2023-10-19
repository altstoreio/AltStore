//
//  LockScreenWidget.swift
//  AltWidget
//
//  Created by Riley Testut on 7/7/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

import AltStoreCore

struct TextLockScreenWidget: Widget
{
    private let kind: String = "TextLockAppDetail"
    
    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 16, *)
        {
            return IntentConfiguration(kind: kind,
                                       intent: ViewAppIntent.self,
                                       provider: AppsTimelineProvider()) { (entry) in
                ComplicationView(entry: entry, style: .text)
            }
            .supportedFamilies([.accessoryCircular])
            .configurationDisplayName("AltWidget (Text)")
            .description("View remaining days until AltStore expires.")
        }
        else
        {
            return EmptyWidgetConfiguration()
        }
    }
}

struct IconLockScreenWidget: Widget
{
    private let kind: String = "IconLockAppDetail"
    
    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 16, *)
        {
            return IntentConfiguration(kind: kind,
                                       intent: ViewAppIntent.self,
                                       provider: AppsTimelineProvider()) { (entry) in
                ComplicationView(entry: entry, style: .icon)
            }
            .supportedFamilies([.accessoryCircular])
            .configurationDisplayName("AltWidget (Icon)")
            .description("View remaining days until AltStore expires.")
        }
        else
        {
            return EmptyWidgetConfiguration()
        }
    }
}

@available(iOS 16, *)
extension ComplicationView
{
    fileprivate enum Style
    {
        case text
        case icon
    }
}

@available(iOS 16, *)
private struct ComplicationView: View
{
    let entry: AppsEntry
    let style: Style
    
    var body: some View {
        let refreshedDate = self.entry.apps.first?.refreshedDate ?? .now
        let expirationDate = self.entry.apps.first?.expirationDate ?? .now
        
        let totalDays = expirationDate.numberOfCalendarDays(since: refreshedDate)
        let daysRemaining = expirationDate.numberOfCalendarDays(since: self.entry.date)
        
        let progress = Double(daysRemaining) / Double(totalDays)
        
        Gauge(value: progress) {
            if daysRemaining < 0
            {
                Text("Expired")
                    .font(.system(size: 10, weight: .bold))
            }
            else
            {
                switch self.style
                {
                case .text:
                    VStack(spacing: -1) {
                        let fontSize = daysRemaining > 99 ? 18.0 : 20.0
                        Text("\(daysRemaining)")
                            .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        
                        Text(daysRemaining == 1 ? "DAY" : "DAYS")
                            .font(.caption)
                    }
                    .fixedSize()
                    .offset(y: -1)
                    
                case .icon:
                    ZStack {
                        // Destination
                        Image("SmallIcon")
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fill)
                            .scaleEffect(x: 0.8, y: 0.8)
                        
                        // Source
                        (
                            daysRemaining > 7 ?
                            Text("7+")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .kerning(-2) :
                                
                            Text("\(daysRemaining)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                         )
                        .foregroundColor(Color.black)
                        .blendMode(.destinationOut) // Clip text out of image.
                    }
                }
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .unredacted()
        .widgetBackground(Color.clear)
    }
}

private let widgetFamily = if #available(iOS 16, *) { WidgetFamily.accessoryCircular } else { WidgetFamily.systemSmall }

#Preview("Text", as: widgetFamily) {
    TextLockScreenWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry(date: Date(), apps: [altstore])
    AppsEntry(date: Date(), apps: [longAltStore])
    
    AppsEntry(date: expiredDate, apps: [altstore])
}

#Preview("Icon", as: widgetFamily) {
    IconLockScreenWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry(date: Date(), apps: [altstore])
    AppsEntry(date: Date(), apps: [longAltStore])
    
    AppsEntry(date: expiredDate, apps: [altstore])
}
