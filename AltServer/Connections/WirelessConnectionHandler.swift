//
//  WirelessConnectionHandler.swift
//  AltKit
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

extension WirelessConnectionHandler
{
    public enum State
    {
        case notRunning
        case connecting
        case running(NWListener.Service)
        case failed(Swift.Error)
    }
}

public class WirelessConnectionHandler: ConnectionHandler
{
    public var connectionHandler: ((Connection) -> Void)?
    public var disconnectionHandler: ((Connection) -> Void)?
    
    public var stateUpdateHandler: ((State) -> Void)?
    
    public private(set) var state: State = .notRunning {
        didSet {
            self.stateUpdateHandler?(self.state)
        }
    }
    
    private lazy var listener = self.makeListener()
    private let dispatchQueue = DispatchQueue(label: "io.altstore.WirelessConnectionListener", qos: .utility)
    
    public func startListening()
    {
        switch self.state
        {
        case .notRunning, .failed: self.listener.start(queue: self.dispatchQueue)
        default: break
        }
    }
    
    public func stopListening()
    {
        switch self.state
        {
        case .running: self.listener.cancel()
        default: break
        }
    }
}

private extension WirelessConnectionHandler
{
    func makeListener() -> NWListener
    {
        let listener = try! NWListener(using: .tcp)
        
        let service: NWListener.Service
        
        if let serverID = UserDefaults.standard.serverID?.data(using: .utf8)
        {
            let txtDictionary = ["serverID": serverID]
            let txtData = NetService.data(fromTXTRecord: txtDictionary)
            
            service = NWListener.Service(name: nil, type: ALTServerServiceType, domain: nil, txtRecord: txtData)
        }
        else
        {
            service = NWListener.Service(type: ALTServerServiceType)
        }
        
        listener.service = service
        
        listener.serviceRegistrationUpdateHandler = { (serviceChange) in
            switch serviceChange
            {
            case .add(.service(let name, let type, let domain, _)):
                let service = NWListener.Service(name: name, type: type, domain: domain, txtRecord: nil)
                self.state = .running(service)
                
            default: break
            }
        }
        
        listener.stateUpdateHandler = { (state) in
            switch state
            {
            case .ready: break
            case .waiting, .setup: self.state = .connecting
            case .cancelled: self.state = .notRunning
            case .failed(let error): self.state = .failed(error)
            @unknown default: break
            }
        }
        
        listener.newConnectionHandler = { [weak self] (connection) in
            self?.prepare(connection)
        }
        
        return listener
    }
    
    func prepare(_ nwConnection: NWConnection)
    {
        print("Preparing:", nwConnection)
        
        // Use same instance for all callbacks.
        let connection = NetworkConnection(nwConnection)
        
        nwConnection.stateUpdateHandler = { [weak self] (state) in
            switch state
            {
            case .setup, .preparing: break
                
            case .ready:
                print("Connected to client:", connection)
                self?.connectionHandler?(connection)
                
            case .waiting:
                print("Waiting for connection...")
                
            case .failed(let error):
                print("Failed to connect to service \(nwConnection.endpoint).", error)
                self?.disconnect(connection)
                
            case .cancelled:
                self?.disconnect(connection)
                
            @unknown default: break
            }
        }
        
        nwConnection.start(queue: self.dispatchQueue)
    }
    
    func disconnect(_ connection: Connection)
    {
        connection.disconnect()
        
        self.disconnectionHandler?(connection)
    }
}
