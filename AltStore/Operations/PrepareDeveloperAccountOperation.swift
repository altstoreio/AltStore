//
//  PrepareDeveloperAccountOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltSign

@objc(PrepareDeveloperAccountOperation)
class PrepareDeveloperAccountOperation: ResultOperation<Void>
{
    let context: AuthenticatedOperationContext
    
    init(context: AuthenticatedOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 2
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
            let team = self.context.team,
            let session = self.context.session
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // Register Device
        self.registerCurrentDevice(for: team, session: session) { (result) in
            let result = result.map { _ in () }
            self.finish(result)
        }
    }
}
         
private extension PrepareDeveloperAccountOperation
{
    func registerCurrentDevice(for team: ALTTeam, session: ALTAppleAPISession, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else {
            return completionHandler(.failure(OperationError.unknownUDID))
        }
        
        ALTAppleAPI.shared.fetchDevices(for: team, session: session) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == udid })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: UIDevice.current.name, identifier: udid, team: team, session: session) { (device, error) in
                        completionHandler(Result(device, error))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
}
