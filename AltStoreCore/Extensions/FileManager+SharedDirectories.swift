//
//  FileManager+SharedDirectories.swift
//  AltStore
//
//  Created by Riley Testut on 5/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

public extension FileManager
{
    var altstoreSharedDirectory: URL? {
        guard let appGroup = Bundle.main.appGroups.first else { return nil }
        
        let sharedDirectoryURL = self.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return sharedDirectoryURL
    }
    
    var appBackupsDirectory: URL? {
        let appBackupsDirectory = self.altstoreSharedDirectory?.appendingPathComponent("Backups", isDirectory: true)
        return appBackupsDirectory
    }
    
    func backupDirectoryURL(for app: InstalledApp) -> URL?
    {
        let backupDirectoryURL = self.appBackupsDirectory?.appendingPathComponent(app.bundleIdentifier, isDirectory: true)
        return backupDirectoryURL
    }
}
