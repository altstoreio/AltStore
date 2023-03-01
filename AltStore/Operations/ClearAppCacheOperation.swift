//
//  ClearAppCacheOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/27/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore

struct BatchError: ALTLocalizedError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = BatchError
        
        case batchError
    }
    
    var code: Code = .batchError
    var underlyingErrors: [Error]
    
    var errorTitle: String?
    var errorFailure: String?
    
    init(errors: [Error])
    {
        self.underlyingErrors = errors
    }
    
    var errorFailureReason: String {
        guard !self.underlyingErrors.isEmpty else { return NSLocalizedString("An unknown error occured.", comment: "") }
        
        let errorMessages = self.underlyingErrors.map { $0.localizedDescription }
        
        let message = errorMessages.joined(separator: "\n\n")
        return message
    }
}

@objc(ClearAppCacheOperation)
class ClearAppCacheOperation: ResultOperation<Void>
{
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    override init()
    {
        self.coordinatorQueue.name = "AltStore - ClearAppCacheOperation Queue"
    }
    
    override func main()
    {
        super.main()
        
        var allErrors = [Error]()
        
        self.clearTemporaryDirectory { result in
            switch result
            {
            case .failure(let batchError as BatchError): allErrors.append(contentsOf: batchError.underlyingErrors)
            case .failure(let error): allErrors.append(error)
            case .success: break
            }
            
            self.removeUninstalledAppBackupDirectories { result in
                switch result
                {
                case .failure(let batchError as BatchError): allErrors.append(contentsOf: batchError.underlyingErrors)
                case .failure(let error): allErrors.append(error)
                case .success: break
                }
                
                if allErrors.isEmpty
                {
                    self.finish(.success(()))
                }
                else
                {
                    let error = BatchError(errors: allErrors)
                    self.finish(.failure(error))
                }
            }
        }
    }
}

private extension ClearAppCacheOperation
{
    func clearTemporaryDirectory(completion: @escaping (Result<Void, Error>) -> Void)
    {
        let intent = NSFileAccessIntent.writingIntent(with: FileManager.default.temporaryDirectory, options: [.forDeleting])
        self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { (error) in
            do
            {
                if let error
                {
                    throw error
                }
                
                let fileURLs = try FileManager.default.contentsOfDirectory(at: intent.url,
                                                                           includingPropertiesForKeys: [],
                                                                           options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                var errors = [Error]()
                
                for fileURL in fileURLs
                {
                    do
                    {
                        print("[ALTLog] Removing item from temporary directory:", fileURL.lastPathComponent)
                        try FileManager.default.removeItem(at: fileURL)
                    }
                    catch
                    {
                        print("[ALTLog] Failed to remove \(fileURL.lastPathComponent) from temporary directory.", error)
                        errors.append(error)
                    }
                }
                
                if !errors.isEmpty
                {
                    let error = BatchError(errors: errors)
                    completion(.failure(error))
                }
                else
                {
                    completion(.success(()))
                }
            }
            catch
            {
                completion(.failure(error))
            }
        }
    }
    
    func removeUninstalledAppBackupDirectories(completion: @escaping (Result<Void, Error>) -> Void)
    {
        guard let backupsDirectory = FileManager.default.appBackupsDirectory else { return completion(.failure(OperationError.missingAppGroup)) }
        
        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            let installedAppBundleIDs = Set(InstalledApp.all(in: context).map { $0.bundleIdentifier })
            
            let intent = NSFileAccessIntent.writingIntent(with: backupsDirectory, options: [.forDeleting])
            self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { (error) in
                do
                {
                    if let error
                    {
                        throw error
                    }
                    
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: intent.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        completion(.success(()))
                        return
                    }
                    
                    let fileURLs = try FileManager.default.contentsOfDirectory(at: intent.url,
                                                                               includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                                               options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                    var errors = [Error]()
                    
                    for backupDirectory in fileURLs
                    {
                        do
                        {
                            let resourceValues = try backupDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                            guard let isDirectory = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }

                            if isDirectory && !installedAppBundleIDs.contains(bundleID) && !AppManager.shared.isActivelyManagingApp(withBundleID: bundleID)
                            {
                                print("[ALTLog] Removing backup directory for uninstalled app:", bundleID)
                                try FileManager.default.removeItem(at: backupDirectory)
                            }
                        }
                        catch
                        {
                            print("[ALTLog] Failed to remove app backup directory:", error)
                            errors.append(error)
                        }
                    }
                    
                    if !errors.isEmpty
                    {
                        let error = BatchError(errors: errors)
                        completion(.failure(error))
                    }
                    else
                    {
                        completion(.success(()))
                    }
                }
                catch
                {
                    print("[ALTLog] Failed to remove app backup directory:", error)
                    completion(.failure(error))
                }
            }
        }
    }
}
