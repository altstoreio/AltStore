//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

@objc(RemoveAppOperation)
class RemoveAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
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
        
        guard let server = self.context.server, let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { return self.finish(.failure(OperationError.unknownUDID)) }
        
        installedApp.managedObjectContext?.perform {
            let resignedBundleIdentifier = installedApp.resignedBundleIdentifier
            
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): self.finish(.failure(error))
                case .success(let connection):
                    print("Sending remove app request...")
                    
                    let request = RemoveAppRequest(udid: udid, bundleIdentifier: resignedBundleIdentifier)
                    connection.send(request) { (result) in
                        print("Sent remove app request!")
                        
                        switch result
                        {
                        case .failure(let error): self.finish(.failure(error))
                        case .success:
                            print("Waiting for remove app response...")
                            connection.receiveResponse() { (result) in
                                print("Receiving remove app response:", result)
                                
                                switch result
                                {
                                case .failure(let error): self.finish(.failure(error))
                                case .success(.error(let response)): self.finish(.failure(response.error))
                                case .success(.removeApp):
                                    DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                                        self.progress.completedUnitCount += 1
                                        
                                        let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
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

