//
//  AnalyticsManager.swift
//  AltStore
//
//  Created by Riley Testut on 3/31/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AppCenter
import AppCenterAnalytics
import AppCenterCrashes

extension AnalyticsManager
{
    enum EventProperty: String
    {
        case name
        case bundleIdentifier
        case developerName
        case version
        case size
        case tintColor
        case sourceIdentifier
        case sourceURL
    }
    
    enum Event
    {
        case installedApp(InstalledApp)
        case updatedApp(InstalledApp)
        case refreshedApp(InstalledApp)
        
        var name: String {
            switch self
            {
            case .installedApp: return "installed_app"
            case .updatedApp: return "updated_app"
            case .refreshedApp: return "refreshed_app"
            }
        }
        
        var properties: [EventProperty: String] {
            let properties: [EventProperty: String?]
            
            switch self
            {
            case .installedApp(let app), .updatedApp(let app), .refreshedApp(let app):
                let appBundleURL = InstalledApp.fileURL(for: app)
                let appBundleSize = FileManager.default.directorySize(at: appBundleURL)
                
                properties = [
                    .name: app.name,
                    .bundleIdentifier: app.bundleIdentifier,
                    .developerName: app.storeApp?.developerName,
                    .version: app.version,
                    .size: appBundleSize?.description,
                    .tintColor: app.storeApp?.tintColor?.hexString,
                    .sourceIdentifier: app.storeApp?.sourceIdentifier,
                    .sourceURL: app.storeApp?.source?.sourceURL.absoluteString
                ]
            }
            
            return properties.compactMapValues { $0 }
        }
    }
}

class AnalyticsManager
{
    static let shared = AnalyticsManager()
    
    private init()
    {
    }
}

extension AnalyticsManager
{
    func start()
    {
        MSAppCenter.start("bb08e9bb-c126-408d-bf3f-324c8473fd40", withServices:[
            MSAnalytics.self,
            MSCrashes.self
        ])
    }
    
    func trackEvent(_ event: Event)
    {
        let properties = event.properties.reduce(into: [:]) { (properties, item) in
            properties[item.key.rawValue] = item.value
        }
        
        MSAnalytics.trackEvent(event.name, withProperties: properties)
    }
}
