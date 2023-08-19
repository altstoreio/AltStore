//
//  RefreshAllAppsWidgetIntent.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AppIntents

@available(iOS 17, *)
struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    static var isDiscoverable: Bool { false } // Don't show in Shortcuts or Spotlight.
    
    #if !WIDGET_EXTENSION
    private let intent = RefreshAllAppsIntent(presentsNotifications: true)
    #endif
    
    func perform() async throws -> some IntentResult & ProvidesDialog
    {
    #if WIDGET_EXTENSION
        return .result(dialog: "")
    #else
        return try await self.intent.perform()
    #endif
    }
}

// To ensure this intent is handled by the app itself (and not widget extension)
// we need to conform to either `ForegroundContinuableIntent` or `AudioPlaybackIntent`.
// https://mastodon.social/@mgorbach/110812347476671807
//
// Unfortunately `ForegroundContinuableIntent` is marked as unavailable in app extensions,
// so we conform to AudioPlaybackIntent instead despite not playing audio ¯\_(ツ)_/¯
@available(iOS 17, *)
extension RefreshAllAppsWidgetIntent: AudioPlaybackIntent {}
