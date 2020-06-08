//
//  LocalConnectionHandler.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit

private let ReceivedLocalServerConnectionRequest: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void =
{ (center, observer, name, object, userInfo) in
    guard let name = name, let observer = observer else { return }
    
    let connection = unsafeBitCast(observer, to: LocalConnectionHandler.self)
    connection.handle(name)
}

class LocalConnectionHandler: ConnectionHandler
{
    var connectionHandler: ((Connection) -> Void)?
    var disconnectionHandler: ((Connection) -> Void)?
    
    private let dispatchQueue = DispatchQueue(label: "io.altstore.LocalConnectionListener", qos: .utility)
    
    deinit
    {
        self.stopListening()
    }
        
    func startListening()
    {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        CFNotificationCenterAddObserver(notificationCenter, observer, ReceivedLocalServerConnectionRequest, CFNotificationName.localServerConnectionAvailableRequest.rawValue, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(notificationCenter, observer, ReceivedLocalServerConnectionRequest, CFNotificationName.localServerConnectionStartRequest.rawValue, nil, .deliverImmediately)
    }
    
    func stopListening()
    {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        CFNotificationCenterRemoveObserver(notificationCenter, observer, .localServerConnectionAvailableRequest, nil)
        CFNotificationCenterRemoveObserver(notificationCenter, observer, .localServerConnectionStartRequest, nil)
    }
    
    fileprivate func handle(_ notification: CFNotificationName)
    {
        switch notification
        {
        case .localServerConnectionAvailableRequest:
            let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
            CFNotificationCenterPostNotification(notificationCenter, .localServerConnectionAvailableResponse, nil, nil, true)

        case .localServerConnectionStartRequest:
            let connection = NWConnection(host: "localhost", port: NWEndpoint.Port(rawValue: ALTDeviceListeningSocket)!, using: .tcp)
            self.start(connection)

        default: break
        }
    }
}

private extension LocalConnectionHandler
{
    func start(_ nwConnection: NWConnection)
    {
        print("Starting connection to:", nwConnection)
        
        // Use same instance for all callbacks.
        let connection = NetworkConnection(nwConnection)
        
        nwConnection.stateUpdateHandler = { [weak self] (state) in
            switch state
            {
            case .setup, .preparing: break
                
            case .ready:
                print("Connected to client:", nwConnection.endpoint)
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
