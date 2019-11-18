//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit
import AltSign
import Roxas

@objc(InstallAppOperation)
class InstallAppOperation: ResultOperation<InstalledApp>
{
    let context: AppOperationContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let resignedApp = self.context.resignedApp,
            let connection = self.context.connection,
            let server = self.context.group.server
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        backgroundContext.perform {
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: resignedApp, originalBundleIdentifier: self.context.bundleIdentifier, context: backgroundContext)
            }
            
            installedApp.version = resignedApp.version
            
            if let profile = resignedApp.provisioningProfile
            {
                installedApp.refreshedDate = profile.creationDate
                installedApp.expirationDate = profile.expirationDate
            }
            
            self.context.group.beginInstallationHandler?(installedApp)
            
            let request = BeginInstallationRequest()
            server.send(request, via: connection) { (result) in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success:
                    
                    self.receive(from: connection, server: server) { (result) in
                        switch result
                        {
                        case .success:
                            backgroundContext.perform {
                                installedApp.refreshedDate = Date()
                                self.finish(.success(installedApp))
                            }
                            
                        case .failure(let error):
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        }
    }
    
    func receive(from connection: NWConnection, server: Server, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        server.receiveResponse(from: connection) { (result) in
            do
            {
                let response = try result.get()
                print(response)
                
                switch response
                {
                case .installationProgress(let response):
                    if response.progress == 1.0
                    {
                        self.progress.completedUnitCount = self.progress.totalUnitCount
                        completionHandler(.success(()))
                    }
                    else
                    {
                        self.progress.completedUnitCount = Int64(response.progress * 100)
                        self.receive(from: connection, server: server, completionHandler: completionHandler)
                    }
                    
                case .error(let response):
                    completionHandler(.failure(response.error))
                    
                default:
                    completionHandler(.failure(ALTServerError(.unknownRequest)))
                }
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
}
