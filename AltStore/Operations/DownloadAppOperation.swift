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
    
    private let downloadURL: URL
    private let ipaURL: URL
    
    private let session = URLSession(configuration: .default)
    
    init(app: App)
    {
        self.app = app
        self.downloadURL = app.downloadURL
        self.ipaURL = InstalledApp.ipaURL(for: app)
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main()
    {
        super.main()
        
        func finish(error: Error?)
        {
            if let error = error
            {
                self.finish(.failure(error))
            }
            else
            {
                self.context.perform {
                    let app = self.context.object(with: self.app.objectID) as! App
                    
                    let installedApp: InstalledApp
                    
                    if let app = app.installedApp
                    {
                        installedApp = app
                        
                    }
                    else
                    {
                        installedApp = InstalledApp(app: app,
                                                    bundleIdentifier: app.identifier,
                                                    expirationDate: Date(),
                                                    context: self.context)
                    }
                    
                    installedApp.version = app.version
                    self.finish(.success(installedApp))
                }
            }
        }
        
        if self.useCachedAppIfAvailable && FileManager.default.fileExists(atPath: self.ipaURL.path)
        {
            finish(error: nil)
            return
        }
        
        let downloadTask = self.session.downloadTask(with: self.downloadURL) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                
                try FileManager.default.copyItem(at: fileURL, to: self.ipaURL, shouldReplace: true)
                
                finish(error: nil)
            }
            catch let error
            {
                finish(error: error)
            }
        }
        
        self.progress.addChild(downloadTask.progress, withPendingUnitCount: 1)
        downloadTask.resume()
    }
}
