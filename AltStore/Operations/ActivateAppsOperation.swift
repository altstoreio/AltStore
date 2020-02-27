//
//  ActivateAppsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/26/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import AltKit

import Roxas

@objc(ActivateAppsOperation)
class ActivateAppsOperation: ResultOperation<[ALTProvisioningProfile: Error]>
{
    let group: OperationGroup
    
    init(group: OperationGroup)
    {
        self.group = group
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.group.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let server = self.group.server else { return self.finish(.failure(OperationError.invalidParameters)) }
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { return self.finish(.failure(OperationError.unknownUDID)) }
        
        ServerManager.shared.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error):
                self.finish(.failure(error))
            case .success(let connection):
                print("Sending activate apps request...")
                
                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    var profiles = Set<ALTProvisioningProfile>()
                    
                    for installedApp in InstalledApp.all(in: context)
                    {
                        guard let app = ALTApplication(fileURL: installedApp.fileURL) else { continue }
                        guard let provisioningProfile = app.provisioningProfile else { continue }
                        
                        guard app.bundleIdentifier != StoreApp.altstoreAppID && app.bundleIdentifier != StoreApp.alternativeAltStoreAppID else { continue }
                        
                        profiles.insert(provisioningProfile)
                        
                        for appExtension in app.appExtensions
                        {
                            guard let provisioningProfile = appExtension.provisioningProfile else { continue }
                            profiles.insert(provisioningProfile)
                        }
                    }
                    
                    let request = ReplaceProvisioningProfilesRequest(udid: udid, provisioningProfiles: profiles)
                    connection.send(request) { (result) in
                        print("Sent activate apps request!")
                        
                        switch result
                        {
                        case .failure(let error): self.finish(.failure(error))
                        case .success:
                            print("Waiting for activate apps response...")
                            connection.receiveResponse() { (result) in
                                print("Receiving activate apps response:", result)
                                
                                switch result
                                {
                                case .failure(let error): self.finish(.failure(error))
                                case .success(.error(let response)): self.finish(.failure(response.error))
                                case .success(.replaceProvisioningProfiles(let response)): self.finish(.success(response.errors))
                                case .success: self.finish(.failure(ALTServerError(.unknownRequest)))
                                }
                            }
                        }
                    }
                    
                }
            }
        }
    }
}
