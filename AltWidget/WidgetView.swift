//
//  WidgetView.swift
//  AltStore
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import WidgetKit
import SwiftUI

import AltStoreCore
import AltSign
import CoreData

struct WidgetView : View
{
    var entry: AppEntry
    
    var body: some View {
        Group {
            if let app = self.entry.app
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: Date())
                    
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {                            
                            VStack(alignment: .leading, spacing: 5) {
                                let imageHeight = geometry.size.height * 0.45
                                
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
                            
                            HStack(alignment: .bottom) {
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
                                              endDate: app.expirationDate)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .opacity(0.8)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .offset(x: 5)
                                }
                            }
                            .offset(y: 5) // Offset so we don't affect layout, but still leave space between app name and Countdown.
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding()
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
        .background(backgroundView(icon: entry.app?.icon, tintColor: entry.app?.tintColor))
    }
}

private extension WidgetView
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

struct WidgetView_Previews: PreviewProvider {
    static var previews: some View {
        let shortRefreshedDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let shortExpirationDate = Calendar.current.date(byAdding: .day, value: 7, to: shortRefreshedDate) ?? Date()
        
        let longRefreshedDate = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        let longExpirationDate = Calendar.current.date(byAdding: .day, value: 365, to: longRefreshedDate) ?? Date()
        
        let altstore = AppSnapshot(name: "AltStore",
                              bundleIdentifier: "com.rileytestut.AltStore",
                              expirationDate: shortExpirationDate,
                              refreshedDate: shortRefreshedDate,
                              tintColor: .altPrimary,
                              icon: UIImage(named: "AltStore"))
        
        let delta = AppSnapshot(name: "Delta",
                              bundleIdentifier: "com.rileytestut.Delta",
                              expirationDate: longExpirationDate,
                              refreshedDate: longRefreshedDate,
                              tintColor: .deltaPrimary,
                              icon: UIImage(named: "Delta"))
        
        return Group {
            WidgetView(entry: AppEntry(date: Date(), app: altstore))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            WidgetView(entry: AppEntry(date: Date(), app: delta))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            WidgetView(entry: AppEntry(date: Date(), app: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            WidgetView(entry: AppEntry(date: Date(), app: nil, isPlaceholder: true))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
}
