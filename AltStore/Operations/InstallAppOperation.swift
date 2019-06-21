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
import Roxas

@objc(InstallAppOperation)
class InstallAppOperation: ResultOperation<Void>
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
            let installedApp = self.context.installedApp,
            let connection = self.context.connection,
            let server = self.context.group.server
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        installedApp.managedObjectContext?.perform {
            print("Installing app:", installedApp.app.identifier)
            self.context.group.beginInstallationHandler?(installedApp)
        }
        
        let request = BeginInstallationRequest()
        server.send(request, via: connection) { (result) in
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success:
                
                self.receive(from: connection, server: server) { (result) in
                    self.finish(result)
                }
            }
        }
    }
    
    func receive(from connection: NWConnection, server: Server, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        server.receive(ServerResponse.self, from: connection) { (result) in
            do
            {
                let response = try result.get()
                print(response)
                
                if let error = response.error
                {
                    self.finish(.failure(error))
                }
                else if response.progress == 1.0
                {
                    self.finish(.success(()))
                }
                else
                {
                    self.progress.completedUnitCount = Int64(response.progress * 100)
                    self.receive(from: connection, server: server, completionHandler: completionHandler)
                }
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
}
