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
        
        let downloadTask = self.session.downloadTask(with: self.downloadURL) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                
                try FileManager.default.copyItem(at: fileURL, to: self.ipaURL, shouldReplace: true)

                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let app = context.object(with: self.app.objectID) as! App
                    
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
                                                    context: context)
                    }
                    
                    installedApp.version = app.version
                    self.finish(.success(installedApp))
                }
            }
            catch let error
            {
                self.finish(.failure(error))
            }
        }
        
        self.progress.addChild(downloadTask.progress, withPendingUnitCount: 1)
        downloadTask.resume()
    }
}
