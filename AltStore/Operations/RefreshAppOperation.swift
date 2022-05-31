//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(RefreshAppOperation)
class RefreshAppOperation: ResultOperation<InstalledApp>
{
    let context: AppOperationContext
    
    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext
    
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
            
            guard let server = self.context.server, let profiles = self.context.provisioningProfiles else { throw OperationError.invalidParameters }
            
            guard let app = self.context.app else { throw OperationError.appNotFound }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
            
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success(let connection):
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                        print("Sending refresh app request...")
                        
                        var activeProfiles: Set<String>?
                        if UserDefaults.standard.activeAppsLimit != nil
                        {
                            // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
                            let activeApps = InstalledApp.fetchActiveApps(in: context)
                            activeProfiles = Set(activeApps.flatMap { (installedApp) -> [String] in
                                let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                                return [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                            })
                        }
                        
                        let request = InstallProvisioningProfilesRequest(udid: udid, provisioningProfiles: Set(profiles.values), activeProfiles: activeProfiles)
                        connection.send(request) { (result) in
                            print("Sent refresh app request!")
                            
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success:
                                print("Waiting for refresh app response...")
                                connection.receiveResponse() { (result) in
                                    print("Receiving refresh app response:", result)
                                    
                                    switch result
                                    {
                                    case .failure(let error): self.finish(.failure(error))
                                    case .success(.error(let response)): self.finish(.failure(response.error))
                                        
                                    case .success(.installProvisioningProfiles):
                                        self.managedObjectContext.perform {
                                            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
                                            guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                                                return self.finish(.failure(OperationError.appNotFound))
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
