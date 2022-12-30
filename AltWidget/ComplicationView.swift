//
//  ComplicationView.swift
//  AltStore
//
//  Created by Riley Testut on 7/7/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

@available(iOS 16, *)
extension ComplicationView
{
    enum Style
    {
        case text
        case icon
    }
}

@available(iOS 16, *)
struct ComplicationView: View
{
    let entry: AppEntry
    let style: Style
    
    var body: some View {
        let refreshedDate = self.entry.app?.refreshedDate ?? .now
        let expirationDate = self.entry.app?.expirationDate ?? .now
        
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
    }
}

@available(iOS 16, *)
struct ComplicationView_Previews: PreviewProvider {
    static var previews: some View {
        let shortRefreshedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let shortExpirationDate = Calendar.current.date(byAdding: .day, value: 7, to: shortRefreshedDate) ?? Date()
        
        let longRefreshedDate = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        let longExpirationDate = Calendar.current.date(byAdding: .day, value: 365, to: longRefreshedDate) ?? Date()
        
        let expiredDate = shortExpirationDate.addingTimeInterval(1 * 60 * 60 * 24)
        
        let weekAltstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: Bundle.Info.appbundleIdentifier,
                              expirationDate: shortExpirationDate,
                              refreshedDate: shortRefreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        let yearAltstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: Bundle.Info.appbundleIdentifier,
                              expirationDate: longExpirationDate,
                              refreshedDate: longRefreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        return Group {
            ComplicationView(entry: AppEntry(date: Date(), app: weekAltstore), style: .icon)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: expiredDate, app: weekAltstore), style: .icon)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: longRefreshedDate, app: yearAltstore), style: .icon)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: Date(), app: weekAltstore), style: .text)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: expiredDate, app: weekAltstore), style: .text)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: longRefreshedDate, app: yearAltstore), style: .text)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))            
        }
    }
}
