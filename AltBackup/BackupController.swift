//
//  BackupController.swift
//  AltBackup
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign

extension Error
{
    var sourceDescription: String? {
        guard let sourceFile = (self as NSError).userInfo[ALTSourceFileErrorKey] as? String, let sourceFileLine = (self as NSError).userInfo[ALTSourceLineErrorKey] else {
            return nil
        }
        return "(\((sourceFile as NSString).lastPathComponent), Line \(sourceFileLine))"
    }
}

extension BackupError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = BackupError
        
        case invalidBundleID
        case appGroupNotFound
        case randomError // Used for debugging.
    }
    
    static func invalidBundleID(description: String, file: String = #file, line: UInt = #line) -> BackupError
    {
        BackupError(code: .invalidBundleID, errorFailure: description, sourceFile: file, sourceLine: line)
    }
    
    static func appGroupNotFound(groupID: String?, description: String, file: String = #file, line: UInt = #line) -> BackupError
    {
        BackupError(code: .appGroupNotFound, appGroupID: groupID, errorFailure: description, sourceFile: file, sourceLine: line)
    }
    
    static func randomError(description: String, file: String = #file, line: UInt = #line) -> BackupError
    {
        BackupError(code: .randomError, errorFailure: description, sourceFile: file, sourceLine: line)
    }
}

struct BackupError: ALTLocalizedError
{
    let code: Code
    
    var appGroupID: String?
    
    var errorTitle: String?
    var errorFailure: String?
    
    var sourceFile: String?
    var sourceLine: UInt?

    var errorFailureReason: String {
        switch self.code
        {
        case .invalidBundleID: return NSLocalizedString("The bundle identifier is invalid.", comment: "")
        case .appGroupNotFound:
            if let appGroup = self.appGroupID
            {
                return String(format: NSLocalizedString("The app group “%@” could not be found.", comment: ""), appGroup)
            }
            else
            {
                return NSLocalizedString("The AltStore app group could not be found.", comment: "")
            }
        case .randomError: return NSLocalizedString("A random error occured.", comment: "")
        }
    }
    
    var errorUserInfo: [String : Any] {
        let userInfo: [String: Any?] = [NSLocalizedDescriptionKey: self.errorDescription,
                                        NSLocalizedFailureReasonErrorKey: self.failureReason,
                                        NSLocalizedFailureErrorKey: self.errorFailure,
                                        ALTSourceFileErrorKey: self.sourceFile,
                                        ALTSourceLineErrorKey: self.sourceLine,
                                        "ALTAppGroupID": self.appGroupID
        ]
        return userInfo.compactMapValues { $0 }
    }
}

class BackupController: NSObject
{
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private let operationQueue = OperationQueue()
    
    override init()
    {
        self.operationQueue.name = "AltBackup-BackupQueue"
    }
    
    func performBackup(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            guard let bundleIdentifier = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.altBundleID) as? String else {
                throw BackupError.invalidBundleID(description: NSLocalizedString("Unable to create backup directory.", comment: ""))
            }
            
            guard
                let altstoreAppGroup = Bundle.main.altstoreAppGroup,
                let sharedDirectoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: altstoreAppGroup)
            else { throw BackupError.appGroupNotFound(groupID: nil, description: NSLocalizedString("Unable to create backup directory.", comment: "")) }
            
            let backupsDirectory = sharedDirectoryURL.appendingPathComponent("Backups")
            
            // Use temporary directory to prevent messing up successful backup with incomplete one.
            let temporaryAppBackupDirectory = backupsDirectory.appendingPathComponent("Temp", isDirectory: true).appendingPathComponent(UUID().uuidString)
            let appBackupDirectory = backupsDirectory.appendingPathComponent(bundleIdentifier)
            
            let writingIntent = NSFileAccessIntent.writingIntent(with: temporaryAppBackupDirectory, options: [])
            let replacementIntent = NSFileAccessIntent.writingIntent(with: appBackupDirectory, options: [.forReplacing])
            self.fileCoordinator.coordinate(with: [writingIntent, replacementIntent], queue: self.operationQueue) { (error) in
                do
                {
                    if let error = error
                    {
                        throw error
                    }
                    
                    do
                    {                        
                        let mainGroupBackupDirectory = temporaryAppBackupDirectory.appendingPathComponent("App")
                        try FileManager.default.createDirectory(at: mainGroupBackupDirectory, withIntermediateDirectories: true, attributes: nil)
                        
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let backupDocumentsDirectory = mainGroupBackupDirectory.appendingPathComponent(documentsDirectory.lastPathComponent)
                        
                        if FileManager.default.fileExists(atPath: backupDocumentsDirectory.path)
                        {
                            try FileManager.default.removeItem(at: backupDocumentsDirectory)
                        }
                        
                        if FileManager.default.fileExists(atPath: documentsDirectory.path)
                        {
                            try FileManager.default.copyItem(at: documentsDirectory, to: backupDocumentsDirectory)
                        }
                        
                        print("Copied Documents directory from \(documentsDirectory) to \(backupDocumentsDirectory)")
                        
                        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                        let backupLibraryDirectory = mainGroupBackupDirectory.appendingPathComponent(libraryDirectory.lastPathComponent)
                        
                        if FileManager.default.fileExists(atPath: backupLibraryDirectory.path)
                        {
                            try FileManager.default.removeItem(at: backupLibraryDirectory)
                        }
                        
                        if FileManager.default.fileExists(atPath: libraryDirectory.path)
                        {
                            try FileManager.default.copyItem(at: libraryDirectory, to: backupLibraryDirectory)
                        }
                        
                        print("Copied Library directory from \(libraryDirectory) to \(backupLibraryDirectory)")
                    }
                    
                    for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup
                    {
                        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                            throw BackupError.appGroupNotFound(groupID: appGroup, description: NSLocalizedString("Unable to create app group backup directory.", comment: ""))
                        }
                        
                        let backupAppGroupURL = temporaryAppBackupDirectory.appendingPathComponent(appGroup)
                        
                        // There are several system hidden files that we don't have permission to read, so we just skip all hidden files in app group directories.
                        try self.copyDirectoryContents(at: appGroupURL, to: backupAppGroupURL, options: [.skipsHiddenFiles])
                    }
                    
                    // Replace previous backup with new backup.
                    _ = try FileManager.default.replaceItemAt(appBackupDirectory, withItemAt: temporaryAppBackupDirectory)
                    
                    print("Replaced previous backup with new backup:", temporaryAppBackupDirectory)
                    
                    completionHandler(.success(()))
                }
                catch
                {
                    do { try FileManager.default.removeItem(at: temporaryAppBackupDirectory) }
                    catch { print("Failed to remove temporary directory.", error) }
                    
                    completionHandler(.failure(error))
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func restoreBackup(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            guard let bundleIdentifier = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.altBundleID) as? String else {
                throw BackupError.invalidBundleID(description: NSLocalizedString("Unable to access backup.", comment: ""))
            }
            
            guard
                let altstoreAppGroup = Bundle.main.altstoreAppGroup,
                let sharedDirectoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: altstoreAppGroup)
            else { throw BackupError.appGroupNotFound(groupID: nil, description: NSLocalizedString("Unable to access backup.", comment: "")) }
            
            let backupsDirectory = sharedDirectoryURL.appendingPathComponent("Backups")
            let appBackupDirectory = backupsDirectory.appendingPathComponent(bundleIdentifier)
            
            let readingIntent = NSFileAccessIntent.readingIntent(with: appBackupDirectory, options: [])
            self.fileCoordinator.coordinate(with: [readingIntent], queue: self.operationQueue) { (error) in
                do
                {
                    if let error = error
                    {
                        throw error
                    }
                    
                    let mainGroupBackupDirectory = appBackupDirectory.appendingPathComponent("App")
                    
                    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let backupDocumentsDirectory = mainGroupBackupDirectory.appendingPathComponent(documentsDirectory.lastPathComponent)
                    
                    let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    let backupLibraryDirectory = mainGroupBackupDirectory.appendingPathComponent(libraryDirectory.lastPathComponent)
                    
                    try self.copyDirectoryContents(at: backupDocumentsDirectory, to: documentsDirectory)
                    try self.copyDirectoryContents(at: backupLibraryDirectory, to: libraryDirectory)
                    
                    for appGroup in Bundle.main.appGroups where appGroup != altstoreAppGroup
                    {
                        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                            throw BackupError.appGroupNotFound(groupID: appGroup, description: NSLocalizedString("Unable to read app group backup.", comment: ""))
                        }
                        
                        let backupAppGroupURL = appBackupDirectory.appendingPathComponent(appGroup)
                        try self.copyDirectoryContents(at: backupAppGroupURL, to: appGroupURL)
                    }
                    
                    completionHandler(.success(()))
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
}

private extension BackupController
{
    func copyDirectoryContents(at sourceDirectoryURL: URL, to destinationDirectoryURL: URL, options: FileManager.DirectoryEnumerationOptions = []) throws
    {
        guard FileManager.default.fileExists(atPath: sourceDirectoryURL.path) else { return }
        
        if !FileManager.default.fileExists(atPath: destinationDirectoryURL.path)
        {
            try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        for fileURL in try FileManager.default.contentsOfDirectory(at: sourceDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: options)
        {
            let isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            let destinationURL = destinationDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: destinationURL.path)
            {
                do {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                catch CocoaError.fileWriteNoPermission where isDirectory {
                    try self.copyDirectoryContents(at: fileURL, to: destinationURL, options: options)
                    continue
                }
                catch {
                    print(error)
                    throw error
                }
            }
            
            do {
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                print("Copied item from \(fileURL) to \(destinationURL)")
            }
            catch let error where fileURL.lastPathComponent == "Inbox" && fileURL.deletingLastPathComponent().lastPathComponent == "Documents" {
                // Ignore errors for /Documents/Inbox
                print("Failed to copy Inbox directory:", error)
            }
            catch {
                print(error)
                throw error
            }
        }
    }
}
