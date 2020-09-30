//
//  Server.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Network

enum ConnectionError: LocalizedError
{
    case serverNotFound
    case connectionFailed
    case connectionDropped
    
    var failureReason: String? {
        switch self
        {
        case .serverNotFound: return NSLocalizedString("Could not find AltServer.", comment: "")
        case .connectionFailed: return NSLocalizedString("Could not connect to AltServer.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        }
    }
}

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
