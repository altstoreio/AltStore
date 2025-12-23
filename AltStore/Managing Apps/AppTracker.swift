//
//  AppTracker.swift
//  AltStore
//
//  Created by Riley Testut on 7/29/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//
//  HACK: The only reliable way to retrieve AppLibrary.App.installationError is via SwiftUI.
//  As a workaround, we place this dummy SwiftUI view in background and use it to observe AppLibrary events,
//  which are then shared with AppMarketplace via shared AppTracker reference.
//  Yes, I hate this as much as you do.
//

import SwiftUI
import MarketplaceKit

import AltStoreCore

// Necessary to react to AppLibrary.App.installationError changing.
extension MarketplaceKitError: @retroactive Equatable
{
    public static func ==(lhs: MarketplaceKitError, rhs: MarketplaceKitError) -> Bool
    {
        return lhs._code == rhs._code
    }
}

@Observable
class AppTracker
{
    fileprivate(set) var allApps: Set<AppLibrary.App> = []
    
    private var errorsByAppID: [AppleItemID: MarketplaceKitError] = [:]
    
    func setError(_ error: MarketplaceKitError?, for app: AppLibrary.App)
    {
        self.errorsByAppID[app.id] = error
    }
    
    func error(for app: AppLibrary.App) -> Error?
    {
        guard let error = self.errorsByAppID[app.id] else { return nil }
        
        switch error
        {
        case .cancelled: return CancellationError()
        default: return InstallationError(error: error)
        }
    }
    
    func verify(_ app: AppLibrary.App) throws
    {
        if let error = self.error(for: app)
        {
            throw error
        }
    }
}

@available(iOS 18, *)
struct AppTrackerView: View
{
    @State
    private(set) var tracker: AppTracker
    
    @State
    private var appLibrary: AppLibrary = .current
    
    init(tracker: AppTracker)
    {
        self.tracker = tracker
    }
    
    var body: some View {
        List {
            let allApps: [AppLibrary.App] = tracker.allApps.sorted(by: { $0.id < $1.id })
            ForEach(allApps) { app in
                AppRow(app: app)
                    .environment(tracker)
            }
        }
        .onChange(of: appLibrary.installingApps) { oldValue, newValue in
            tracker.allApps.formUnion(newValue)
        }
        .onChange(of: appLibrary.installedApps) { oldValue, newValue in
            tracker.allApps.formUnion(newValue)
        }
        .onAppear {
            tracker.allApps.formUnion(appLibrary.installedApps)
        }
    }
}

@available(iOS 18, *)
private struct AppRow: View
{
    @State
    var app: AppLibrary.App
    
    @Environment(AppTracker.self)
    private var tracker
    
    init(app: AppLibrary.App)
    {
        self.app = app
    }
    
    var body: some View {
        VStack {
            HStack {
                HStack {
                    Text("App ID:")
                    Text("\(app.id.formatted(.number.grouping(.never)))")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(app.isInstalling ? "Installing…" : "Installed")
            }
            
            if let lastError = tracker.error(for: app)
            {
                HStack {
                    Text("Error:")
                    Text("\(lastError.localizedDescription)")
                }
            }
        }
        .onChange(of: app.installationError) { oldValue, newValue in
            guard let newValue else { return }
            self.tracker.setError(newValue, for: app)
        }
    }
}

@available(iOS 18, *)
#Preview {
    AppTrackerView(tracker: AppTracker())
}
