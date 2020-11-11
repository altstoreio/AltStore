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
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>
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
        
        ServerManager.shared.connect(to: server) { (result) in
            switch result
            {
            case .failure(let error):
                self.finish(.failure(error))
            case .success(let connection):
                print("Sending anisette data request...")
                
                let request = AnisetteDataRequest()
                connection.send(request) { (result) in
                    print("Sent anisette data request!")
                    
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success:
                        print("Waiting for anisette data...")
                        connection.receiveResponse() { (result) in
                            print("Receiving anisette data:", result.error?.localizedDescription ?? "success")
                            
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success(.error(let response)): self.finish(.failure(response.error))
                            case .success(.anisetteData(let response)): self.finish(.success(response.anisetteData))
                            case .success: self.finish(.failure(ALTServerError(.unknownRequest)))
                            }
                        }
                    }
                }
            }
        }
    }
}
