//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltSign

@objc(DownloadAppOperation)
class DownloadAppOperation: ResultOperation<InstalledApp>
{
    let app: App
    
    var useCachedAppIfAvailable = false
    lazy var context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
    
    private let appIdentifier: String
    private let sourceURL: URL
    private let destinationURL: URL
    
    private let session = URLSession(configuration: .default)
    
    init(app: App)
    {
        self.app = app
        self.appIdentifier = app.identifier
        self.sourceURL = app.downloadURL
        self.destinationURL = InstalledApp.fileURL(for: app)
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        print("Downloading App:", self.appIdentifier)
        
        func finishOperation(_ result: Result<URL, Error>)
        {
            do
            {
                let fileURL = try result.get()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { throw OperationError.appNotFound }
                
                if isDirectory.boolValue
                {
                    // Directory, so assuming this is .app bundle.
                    guard Bundle(url: fileURL) != nil else { throw OperationError.invalidApp }
                    
                    try FileManager.default.copyItem(at: fileURL, to: self.destinationURL, shouldReplace: true)
                }
                else
                {
                    // File, so assuming this is a .ipa file.
                    
                    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
                    
                    let bundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: temporaryDirectory)
                    try FileManager.default.copyItem(at: bundleURL, to: self.destinationURL, shouldReplace: true)
                }
                
                self.context.perform {
                    let app = self.context.object(with: self.app.objectID) as! App
                    
                    let installedApp: InstalledApp
                    
                    if let app = app.installedApp
                    {
                        installedApp = app
                        
                    }
                    else
                    {
                        installedApp = InstalledApp(app: app, bundleIdentifier: app.identifier, context: self.context)
                    }
                    
                    installedApp.version = app.version
                    self.finish(.success(installedApp))
                }
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
        
        if self.sourceURL.isFileURL
        {
            finishOperation(.success(self.sourceURL))
            
            self.progress.completedUnitCount += 1
        }
        else
        {
            let downloadTask = self.session.downloadTask(with: self.sourceURL) { (fileURL, response, error) in
                do
                {
                    let (fileURL, _) = try Result((fileURL, response), error).get()
                    finishOperation(.success(fileURL))
                }
                catch
                {
                    finishOperation(.failure(error))
                }
            }
            self.progress.addChild(downloadTask.progress, withPendingUnitCount: 1)
            
            downloadTask.resume()
        }
    }
}
