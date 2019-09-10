//
//  FindServerOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/8/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

@objc(FindServerOperation)
class FindServerOperation: ResultOperation<Server>
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
        
        if let server = ServerManager.shared.discoveredServers.first(where: { $0.isPreferred })
        {
            // Preferred server.
            self.finish(.success(server))
        }
        else if let server = ServerManager.shared.discoveredServers.first
        {
            // Any available server.
            self.finish(.success(server))
        }
        else
        {
            // No servers.
            self.finish(.failure(ConnectionError.serverNotFound))
        }
    }
}

