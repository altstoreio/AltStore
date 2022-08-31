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
struct ComplicationView: View
{
    let entry: AppEntry
    
    var body: some View {
        let refreshedDate = self.entry.app?.refreshedDate ?? .now
        let expirationDate = self.entry.app?.expirationDate ?? .now
        
        let totalDays = expirationDate.numberOfCalendarDays(since: refreshedDate)
        let daysRemaining = expirationDate.numberOfCalendarDays(since: self.entry.date)
        
        let progress = Double(daysRemaining) / Double(totalDays)
        
        ZStack(alignment: .center) {
            ProgressRing(progress: progress) {
                if daysRemaining < 0
                {
                    Text("Expired")
                        .font(.system(size: 10, weight: .bold))
                }
                else
                {
                    VStack(spacing: -1) {
                        Text("\(daysRemaining)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        
                        Text(daysRemaining == 1 ? "DAY" : "DAYS")
                            .font(.caption)
                    }
                    .offset(y: -1)
                }
            }
        }
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
                              bundleIdentifier: "com.rileytestut.AltStore",
                              expirationDate: shortExpirationDate,
                              refreshedDate: shortRefreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        let yearAltstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              expirationDate: longExpirationDate,
                              refreshedDate: longRefreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        return Group {
            ComplicationView(entry: AppEntry(date: Date(), app: weekAltstore))
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: expiredDate, app: weekAltstore))
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
            
            ComplicationView(entry: AppEntry(date: longRefreshedDate, app: yearAltstore))
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
        }
    }
}
