//
//  NetworkConnection.swift
//  AltKit
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

public class NetworkConnection: NSObject, Connection
{
    public let nwConnection: NWConnection
    
    public init(_ nwConnection: NWConnection)
    {
        self.nwConnection = nwConnection
    }
    
    public func __send(_ data: Data, completionHandler: @escaping (Bool, Error?) -> Void)
    {
        self.nwConnection.send(content: data, completion: .contentProcessed { (error) in
            completionHandler(error == nil, error)
        })
    }
    
    public func __receiveData(expectedSize: Int, completionHandler: @escaping (Data?, Error?) -> Void)
    {
        self.nwConnection.receive(minimumIncompleteLength: expectedSize, maximumLength: expectedSize) { (data, context, isComplete, error) in
            guard data != nil || error != nil else {
                return completionHandler(nil, ALTServerError(.lostConnection))
            }
            
            completionHandler(data, error)
        }
    }
    
    public func disconnect()
    {
        switch self.nwConnection.state
        {
        case .cancelled, .failed: break
        default: self.nwConnection.cancel()
        }
    }
}

extension NetworkConnection
{
    override public var description: String {
        return "\(self.nwConnection.endpoint) (Network)"
    }
}
