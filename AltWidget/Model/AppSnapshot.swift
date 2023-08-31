//
//  AppsEntry.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import WidgetKit

import AltStoreCore
import AltSign

struct AppSnapshot
{
    var name: String
    var bundleIdentifier: String
    var expirationDate: Date
    var refreshedDate: Date
    
    var tintColor: UIColor?
    var icon: UIImage?
}

extension AppSnapshot
{
    // Declared in extension so we retain synthesized initializer.
    init(installedApp: InstalledApp)
    {
        self.name = installedApp.name
        self.bundleIdentifier = installedApp.bundleIdentifier
        self.expirationDate = installedApp.expirationDate
        self.refreshedDate = installedApp.refreshedDate
        
        self.tintColor = installedApp.storeApp?.tintColor
        
        let application = ALTApplication(fileURL: installedApp.fileURL)
        self.icon = application?.icon?.resizing(toFill: CGSize(width: 180, height: 180))
    }
}
