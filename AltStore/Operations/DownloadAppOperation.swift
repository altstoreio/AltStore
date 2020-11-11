//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltStoreCore
import AltSign

@objc(DownloadAppOperation)
class DownloadAppOperation: ResultOperation<ALTApplication>
{
    let app: AppProtocol
    let context: AppOperationContext
    
    private let bundleIdentifier: String
    private let sourceURL: URL
    private let destinationURL: URL
    
    private let session = URLSession(configuration: .default)
    
    init(app: AppProtocol, destinationURL: URL, context: AppOperationContext)
    {
        self.app = app
        self.context = context
        
        self.bundleIdentifier = app.bundleIdentifier
        self.sourceURL = app.url
        self.destinationURL = destinationURL
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        print("Downloading App:", self.bundleIdentifier)
        
        func finishOperation(_ result: Result<URL, Error>)
        {
            do
            {
                let fileURL = try result.get()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { throw OperationError.appNotFound }
                
                let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
                
                let appBundleURL: URL
                
                if isDirectory.boolValue
                {
                    // Directory, so assuming this is .app bundle.
                    guard Bundle(url: fileURL) != nil else { throw OperationError.invalidApp }
                    
                    appBundleURL = fileURL
                }
                else
                {
                    // File, so assuming this is a .ipa file.
                    appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: temporaryDirectory)
                }
                
                guard let application = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                
                guard ProcessInfo.processInfo.isOperatingSystemAtLeast(application.minimumiOSVersion) else { throw OperationError.iOSVersionNotSupported(application) }
                
                try FileManager.default.copyItem(at: appBundleURL, to: self.destinationURL, shouldReplace: true)
                
                if self.context.bundleIdentifier == StoreApp.dolphinAppID, self.context.bundleIdentifier != application.bundleIdentifier
                {
                    let infoPlistURL = self.destinationURL.appendingPathComponent("Info.plist")

                    if var infoPlist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
                    {
                        // Manually update the app's bundle identifier to match the one specified in the source.
                        // This allows people who previously installed the app to still update and refresh normally.
                        infoPlist[kCFBundleIdentifierKey as String] = StoreApp.dolphinAppID
                        (infoPlist as NSDictionary).write(to: infoPlistURL, atomically: true)
                    }
                }
                
                guard let copiedApplication = ALTApplication(fileURL: self.destinationURL) else { throw OperationError.invalidApp }
                self.finish(.success(copiedApplication))
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
