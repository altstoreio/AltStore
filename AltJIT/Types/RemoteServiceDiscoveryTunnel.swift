//
//  RemoteServiceDiscoveryTunnel.swift
//  AltJIT
//
//  Created by Riley Testut on 9/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

final class RemoteServiceDiscoveryTunnel
{
    let ipAddress: String
    let port: Int
    
    let process: Process
    
    var commandArguments: [String] {
        ["--rsd", self.ipAddress, String(self.port)]
    }
    
    init(ipAddress: String, port: Int, process: Process)
    {
        self.ipAddress = ipAddress
        self.port = port
        
        self.process = process
    }
    
    deinit
    {
        self.process.terminate()
    }
}

extension RemoteServiceDiscoveryTunnel: CustomStringConvertible
{
    var description: String {
        "\(self.ipAddress) \(self.port)"
    }
}
