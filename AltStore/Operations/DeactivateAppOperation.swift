//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(DeactivateAppOperation)
class DeactivateAppOperation: ResultOperation<InstalledApp>
{
    let app: InstalledApp
    let context: OperationContext
    
    init(app: InstalledApp, context: OperationContext)
    {
        self.app = app
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let server = self.context.server else { return self.finish(.failure(OperationError.invalidParameters)) }
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { return self.finish(.failure(OperationError.unknownUDID)) }
        
        ServerManager.shared.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let connection):
                print("Sending deactivate app request...")
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let installedApp = context.object(with: self.app.objectID) as! InstalledApp
                    
                    let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                    let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                    
                    let request = RemoveProvisioningProfilesRequest(udid: udid, bundleIdentifiers: Set(allIdentifiers))
                    connection.send(request) { (result) in
                        print("Sent deactive app request!")
                        
                        switch result
                        {
                        case .failure(let error): self.finish(.failure(error))
                        case .success:
                            print("Waiting for deactivate app response...")
                            connection.receiveResponse() { (result) in
                                print("Receiving deactivate app response:", result)
                                
                                switch result
                                {
                                case .failure(let error): self.finish(.failure(error))
                                case .success(.error(let response)): self.finish(.failure(response.error))
                                case .success(.removeProvisioningProfiles):
                                    DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                                        self.progress.completedUnitCount += 1
                                        
                                        let installedApp = context.object(with: self.app.objectID) as! InstalledApp
                                        installedApp.isActive = false
                                        self.finish(.success(installedApp))
                                    }
                                    
                                case .success: self.finish(.failure(ALTServerError(.unknownResponse)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
