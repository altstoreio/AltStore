//
//  AppShortcuts.swift
//  AltStore
//
//  Created by Riley Testut on 8/23/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import AppIntents

@available(iOS 17, *)
public struct ShortcutsProvider: AppShortcutsProvider
{
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshAllAppsIntent(), 
                    phrases: [
                        "Refresh \(.applicationName)",
                        "Refresh \(.applicationName) apps",
                        "Refresh my \(.applicationName) apps",
                        "Refresh apps with \(.applicationName)",
                    ],
                    shortTitle: "Refresh All Apps",
                    systemImageName: "arrow.triangle.2.circlepath")
    }
    
    public static var shortcutTileColor: ShortcutTileColor {
        return .teal
    }
}
