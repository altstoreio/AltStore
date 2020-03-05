//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import AltKit

import Roxas

@objc(RefreshAppOperation)
class RefreshAppOperation: ResultOperation<InstalledApp>
{
    let context: AppOperationContext
    let managedObjectContext: NSManagedObjectContext // Keep context alive
    
    init(context: AppOperationContext)
    {
        self.context = context
        self.managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            guard
                let server = self.context.server,
                let app = self.context.app,
                let team = self.context.team,
                let profiles = self.context.provisioningProfiles
            else { throw OperationError.invalidParameters }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
            
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success(let connection):
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                        print("Sending activate apps request...")
                        
                        var activeProfiles: Set<String>?
                        
                        if team.type == .free
                        {
                            let activeApps = InstalledApp.all(satisfying: NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive)), in: context)
                            activeProfiles = Set(activeApps.flatMap { (installedApp) -> [String] in
                                let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                                let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                                return allIdentifiers
                            })
                        }
                        
                        let request = InstallProvisioningProfilesRequest(udid: udid, provisioningProfiles: Set(profiles.values), activeProvisioningProfiles: activeProfiles)
                        connection.send(request) { (result) in
                            print("Sent activate apps request!")
                            
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success:
                                print("Waiting for activate apps response...")
                                connection.receiveResponse() { (result) in
                                    print("Receiving refresh app response:", result)
                                    
                                    switch result
                                    {
                                    case .failure(let error): self.finish(.failure(error))
                                    case .success(.error(let response)): self.finish(.failure(response.error))
                                        
                                    case .success(.installProvisioningProfiles):
                                        self.managedObjectContext.perform {
                                            let predicate = NSPredicate(format: "%K == %@",
                                                                        #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
                                            
                                            guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                                                return self.finish(.failure(OperationError.invalidApp))
                                            }
                                            
                                            self.progress.completedUnitCount += 1
                                            
                                            if let provisioningProfile = profiles[app.bundleIdentifier]
                                            {
                                                installedApp.update(provisioningProfile: provisioningProfile)
                                            }
                                            
                                            for installedExtension in installedApp.appExtensions
                                            {
                                                guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
                                                installedExtension.update(provisioningProfile: provisioningProfile)
                                            }
                                            
                                            self.finish(.success(installedApp))
                                        }
                                        
                                    case .success: self.finish(.failure(ALTServerError(.unknownRequest)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}
