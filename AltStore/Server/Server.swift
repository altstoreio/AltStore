//
//  Server.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Network

import AltKit

extension ALTServerError
{
    init<E: Error>(_ error: E)
    {
        switch error
        {
        case let error as ALTServerError: self = error
        case is DecodingError: self = ALTServerError(.invalidResponse)
        case is EncodingError: self = ALTServerError(.invalidRequest)
        default:
            assertionFailure("Caught unknown error type")
            self = ALTServerError(.unknown)
        }
    }
}

enum ConnectionError: LocalizedError
{
    case serverNotFound
    case connectionFailed
    case connectionDropped
    
    var errorDescription: String? {
        switch self
        {
        case .serverNotFound: return NSLocalizedString("Could not find AltServer.", comment: "")
        case .connectionFailed: return NSLocalizedString("Could not connect to AltServer.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        }
    }
}

struct Server: Equatable
{
    var identifier: String? = nil
    var service: NetService? = nil
    
    var isPreferred = false
    var isWiredConnection = false
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
