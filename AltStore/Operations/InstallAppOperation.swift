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
    
    private var didCleanUp = false
    
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
            let connection = self.context.installationConnection
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
                installedApp.installedDate = Date()
            }
            
            var installedExtensions = Set<InstalledExtension>()
            
            if
                let bundle = Bundle(url: resignedApp.fileURL),
                let directory = bundle.builtInPlugInsURL,
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            {
                for case let fileURL as URL in enumerator
                {
                    guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                    guard let appExtension = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }
                    
                    let installedExtension: InstalledExtension
                    
                    if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == appExtension.bundleIdentifier })
                    {
                        installedExtension = appExtension
                    }
                    else
                    {
                        installedExtension = InstalledExtension(resignedAppExtension: appExtension, originalBundleIdentifier: appExtension.bundleIdentifier, context: backgroundContext)
                        installedExtension.installedDate = Date()
                    }
                    
                    installedExtensions.insert(installedExtension)
                }
            }
            
            installedApp.appExtensions = installedExtensions
            
            installedApp.version = resignedApp.version
            
            if let profile = resignedApp.provisioningProfile
            {
                installedApp.refreshedDate = profile.creationDate
                installedApp.expirationDate = profile.expirationDate
            }
            
            if let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.isActiveTeam), NSNumber(value: true)), in: backgroundContext)
            {
                installedApp.team = team
            }
            
            // Temporary directory and resigned .ipa no longer needed, so delete them now to ensure AltStore doesn't quit before we get the chance to.
            self.cleanUp()
            
            self.context.group.beginInstallationHandler?(installedApp)
            
            let request = BeginInstallationRequest()
            connection.send(request) { (result) in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success:
                    
                    self.receive(from: connection) { (result) in
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
    
    override func finish(_ result: Result<InstalledApp, Error>)
    {
        self.cleanUp()
        
        super.finish(result)
    }
}

private extension InstallAppOperation
{
    func receive(from connection: ServerConnection, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        connection.receiveResponse() { (result) in
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
                        self.receive(from: connection, completionHandler: completionHandler)
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
    
    func cleanUp()
    {
        guard !self.didCleanUp else { return }
        self.didCleanUp = true
        
        do
        {
            try FileManager.default.removeItem(at: self.context.temporaryDirectory)
            
            if let app = self.context.app
            {
                let fileURL = InstalledApp.refreshedIPAURL(for: app)
                try FileManager.default.removeItem(at: fileURL)
            }
        }
        catch
        {
            print("Failed to remove temporary directory.", error)
        }
    }
}
