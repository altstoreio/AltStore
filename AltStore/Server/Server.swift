//
//  Server.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Network

extension Server
{
    enum ConnectionType
    {
        case wireless
        case wired
        case local
    }
}

struct Server: Equatable
{
    var identifier: String? = nil
    var service: NetService? = nil
    
    var isPreferred = false
    var connectionType: ConnectionType = .wireless
    
    var machServiceName: String?
}

extension Server
{
    // Defined in extension so we can still use the automatically synthesized initializer.
    init?(service: NetService, txtData: Data)
    {
        let txtDictionary = NetService.dictionary(fromTXTRecord: txtData)
        guard let identifierData = txtDictionary["serverID"], let identifier = String(data: identifierData, encoding: .utf8) else { return nil }
        
        self.service = service
        self.identifier = identifier
    }
}
