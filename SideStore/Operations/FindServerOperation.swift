//
//  FindServerOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/8/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import Roxas

private let ReceivedServerConnectionResponse: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void =
{ (center, observer, name, object, userInfo) in
    guard let name = name, let observer = observer else { return }
    
    let operation = unsafeBitCast(observer, to: FindServerOperation.self)
    operation.handle(name)
}

@objc(FindServerOperation)
class FindServerOperation: ResultOperation<Server>
{
    let context: OperationContext
    
    private var isWiredServerConnectionAvailable = false
    private var localServerMachServiceName: String?
    
    init(context: OperationContext = OperationContext())
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
        
        if let server = self.context.server
        {
            self.finish(.success(server))
            return
        }
        
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        // Prepare observers to receive callback from wired connection or background daemon (if available).
        CFNotificationCenterAddObserver(notificationCenter, observer, ReceivedServerConnectionResponse, CFNotificationName.wiredServerConnectionAvailableResponse.rawValue, nil, .deliverImmediately)
        
        // Post notifications.
        CFNotificationCenterPostNotification(notificationCenter, .wiredServerConnectionAvailableRequest, nil, nil, true)
        
        self.discoverLocalServer()
        
        // Wait for either callback or timeout.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if let machServiceName = self.localServerMachServiceName
            {
                // Prefer background daemon, if it exists and is running.
                let server = Server(connectionType: .local, machServiceName: machServiceName)
                self.finish(.success(server))
            }
            else if self.isWiredServerConnectionAvailable
            {
                let server = Server(connectionType: .wired)
                self.finish(.success(server))
            }
            else if let server = ServerManager.shared.discoveredServers.first(where: { $0.isPreferred })
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
    
    override func finish(_ result: Result<Server, Error>)
    {
        super.finish(result)
        
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        CFNotificationCenterRemoveObserver(notificationCenter, observer, .wiredServerConnectionAvailableResponse, nil)
    }
}

fileprivate extension FindServerOperation
{
    func discoverLocalServer()
    {
        for machServiceName in XPCConnection.machServiceNames
        {
            let xpcConnection = NSXPCConnection.makeConnection(machServiceName: machServiceName)
            
            let connection = XPCConnection(xpcConnection)
            connection.connect { (result) in
                switch result
                {
                case .failure(let error): print("Could not connect to AltDaemon XPC service \(machServiceName).", error)
                case .success: self.localServerMachServiceName = machServiceName
                }
            }
        }
    }
    
    func handle(_ notification: CFNotificationName)
    {
        switch notification
        {
        case .wiredServerConnectionAvailableResponse: self.isWiredServerConnectionAvailable = true
        default: break
        }
    }
}
