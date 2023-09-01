//
//  AppDetailWidget.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import WidgetKit
import SwiftUI

import AltStoreCore

struct AppDetailWidget: Widget
{
    private let kind: String = "AppDetail"
    
    public var body: some WidgetConfiguration {
        let configuration = IntentConfiguration(kind: kind,
                                   intent: ViewAppIntent.self,
                                   provider: AppsTimelineProvider()) { (entry) in
            AppDetailWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("AltWidget")
        .description("View remaining days until your sideloaded apps expire.")
        
        if #available(iOS 17, *)
        {
            return configuration
                .contentMarginsDisabled()
        }
        else
        {
            return configuration
        }
    }
}

private struct AppDetailWidgetView: View
{
    var entry: AppsEntry
    
    var body: some View {
        Group {
            if let app = self.entry.apps.first
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: self.entry.date)
                    
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                let imageHeight = geometry.size.height * 0.4
                                
                                Image(uiImage: app.icon ?? UIImage())
                                    .resizable()
                                    .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                    .frame(height: imageHeight)
                                    .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: .continuous))
                                
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer(minLength: 0)
                            
                            HStack(alignment: .center) {
                                let expirationText: Text = {
                                    switch daysRemaining
                                    {
                                    case ..<0: return Text("Expired")
                                    case 1: return Text("1 day")
                                    default: return Text("\(daysRemaining) days")
                                    }
                                }()
                                
                                (
                                    Text("Expires in\n")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.45)) +
                                    
                                    expirationText
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                                .lineLimit(2)
                                .lineSpacing(1.0)
                                .minimumScaleFactor(0.5)
                                
                                Spacer()
                                
                                if daysRemaining >= 0
                                {
                                    Countdown(startDate: app.refreshedDate,
                                              endDate: app.expirationDate,
                                              currentDate: self.entry.date)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .opacity(0.8)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .offset(x: 5)
                                        .invalidatableContentIfAvailable()
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .activatesRefreshAllAppsIntent()
                        }
                        .padding()
                    }
                }
            }
            else
            {
                VStack {
                    // Put conditional inside VStack, or else an empty view will be returned
                    // if isPlaceholder == false, which messes up layout.
                    if !entry.isPlaceholder
                    {
                        Text("App Not Found")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetBackground(backgroundView(icon: entry.apps.first?.icon, tintColor: entry.apps.first?.tintColor))
    }
}

private extension AppDetailWidgetView
{
    func backgroundView(icon: UIImage? = nil, tintColor: UIColor? = nil) -> some View
    {
        let icon = icon ?? UIImage(named: "AltStore")!
        let tintColor = tintColor ?? .gray
        
        let imageHeight = 60 as CGFloat
        let saturation = 1.8
        let blurRadius = 5 as CGFloat
        let tintOpacity = 0.45
        
        return ZStack(alignment: .topTrailing) {
            // Blurred Image
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageHeight, height: imageHeight, alignment: .center)
                        .saturation(saturation)
                        .blur(radius: blurRadius, opaque: true)
                        .scaleEffect(geometry.size.width / imageHeight, anchor: .center)
                    
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

#Preview(as: .systemSmall) {
    AppDetailWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, delta, clip, _, longDelta, _) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry(date: Date(), apps: [altstore])
    AppsEntry(date: Date(), apps: [delta])
    AppsEntry(date: Date(), apps: [longDelta])
    
    AppsEntry(date: expiredDate, apps: [delta])
    
    AppsEntry(date: Date(), apps: [])
    AppsEntry(date: Date(), apps: [], isPlaceholder: true)
}
