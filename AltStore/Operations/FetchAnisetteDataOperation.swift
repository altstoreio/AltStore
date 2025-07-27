//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, @unchecked Sendable
{
    let context: OperationContext
    
    init(context: OperationContext)
    {
        self.context = context
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
        
        Logger.sideload.notice("Fetching anisette data...")
        
        ServerManager.shared.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error):
                self.finish(.failure(error))
            case .success(let connection):
                Logger.sideload.debug("Sending anisette data request...")
                
                let request = AnisetteDataRequest()
                connection.send(request) { (result) in
                    switch result
                    {
                    case .failure(let error):
                        Logger.sideload.error("Failed to send anisette data request. \(error.localizedDescription, privacy: .public)")
                        self.finish(.failure(error))
                        
                    case .success:
                        Logger.sideload.debug("Waiting for anisette data...")
                        connection.receiveResponse() { (result) in
                            switch result
                            {
                            case .failure(let error): 
                                Logger.sideload.error("Failed to receive anisette data response. \(error.localizedDescription, privacy: .public)")
                                self.finish(.failure(error))
                                
                            case .success(.error(let response)): 
                                Logger.sideload.error("Failed to receive anisette data. \(response.error.localizedDescription, privacy: .public)")
                                self.finish(.failure(response.error))
                                
                            case .success(.anisetteData(let response)):
                                Logger.sideload.info("Successfully received anisette data!")
                                self.finish(.success(response.anisetteData))
                                
                            case .success: self.finish(.failure(ALTServerError(.unknownResponse)))
                            }
                        }
                    }
                }
            }
        }
    }
}
