//
//  RemoveAppBackupOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/13/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

@objc(RemoveAppBackupOperation)
class RemoveAppBackupOperation: ResultOperation<Void>, @unchecked Sendable
{
    let context: InstallAppOperationContext
    
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.coordinatorQueue.name = "AltStore - RemoveAppBackupOperation Queue"
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        Logger.sideload.notice("Removing backup for app \(self.context.bundleIdentifier, privacy: .public)...")
        
        installedApp.managedObjectContext?.perform {
            guard let backupDirectoryURL = FileManager.default.backupDirectoryURL(for: installedApp) else { return self.finish(.failure(OperationError.missingAppGroup)) }
            
            let intent = NSFileAccessIntent.writingIntent(with: backupDirectoryURL, options: [.forDeleting])
            self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { (error) in
                do
                {
                    if let error = error
                    {
                        throw error
                    }
                    
                    try FileManager.default.removeItem(at: intent.url)
                    
                    self.finish(.success(()))
                }
                catch let error as CocoaError where error.code == CocoaError.Code.fileNoSuchFile
                {
                    #if DEBUG
                    
                    // When debugging, it's expected that app groups don't match, so ignore.
                    self.finish(.success(()))
                    
                    #else
                    
                    Logger.sideload.error("Failed to remove app backup directory \(backupDirectoryURL.lastPathComponent, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    self.finish(.failure(error))
                    
                    #endif
                }
                catch
                {
                    Logger.sideload.error("Failed to remove app backup directory \(backupDirectoryURL.lastPathComponent, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    self.finish(.failure(error))
                }
            }
        }
    }
}
