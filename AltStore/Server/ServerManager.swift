//
//  ServerManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltStoreCore

class ServerManager: NSObject
{
    static let shared = ServerManager()
    
    private(set) var isDiscovering = false
    private(set) var discoveredServers = [Server]()
    
    private let serviceBrowser = NetServiceBrowser()
    private var services = Set<NetService>()
    
    private let dispatchQueue = DispatchQueue(label: "io.altstore.ServerManager")
    
    private var connectionListener: NWListener?
    private var incomingConnections: [NWConnection]?
    private var incomingConnectionsSemaphore: DispatchSemaphore?
    
    private override init()
    {
        super.init()
        
        self.serviceBrowser.delegate = self
        self.serviceBrowser.includesPeerToPeer = false
    }
}

extension ServerManager
{
    func startDiscovering()
    {
        guard !self.isDiscovering else { return }
        self.isDiscovering = true
        
        self.serviceBrowser.searchForServices(ofType: ALTServerServiceType, inDomain: "")
        
        self.startListeningForWiredConnections()
    }
    
    func stopDiscovering()
    {
        guard self.isDiscovering else { return }
        self.isDiscovering = false
        
        self.discoveredServers.removeAll()
        self.services.removeAll()
        self.serviceBrowser.stop()
        
        self.stopListeningForWiredConnection()
    }
    
    func connect(to server: Server, completion: @escaping (Result<ServerConnection, Error>) -> Void)
    {
        DispatchQueue.global().async {
            func finish(_ result: Result<Connection, Error>)
            {
                switch result
                {
                case .failure(let error): completion(.failure(error))
                case .success(let connection):
                    let serverConnection = ServerConnection(server: server, connection: connection)
                    completion(.success(serverConnection))
                }
            }
            
            switch server.connectionType
            {
            case .local: self.connectToLocalServer(server, completion: finish(_:))
            case .wired:
                guard let incomingConnectionsSemaphore = self.incomingConnectionsSemaphore else { return finish(.failure(ALTServerError(.connectionFailed))) }
                
                print("Waiting for incoming connection...")
                
                let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
                                
                switch server.connectionType
                {
                case .wired: CFNotificationCenterPostNotification(notificationCenter, .wiredServerConnectionStartRequest, nil, nil, true)
                case .local, .wireless: break
                }
                
                _ = incomingConnectionsSemaphore.wait(timeout: .now() + 10.0)
                
                if let connection = self.incomingConnections?.popLast()
                {
                    self.connectToRemoteServer(server, connection: connection, completion: finish(_:))
                }
                else
                {
                    finish(.failure(ALTServerError(.connectionFailed)))
                }
                
            case .wireless:
                guard let service = server.service else { return finish(.failure(ALTServerError(.connectionFailed))) }
                
                print("Connecting to service:", service)
                
                let connection = NWConnection(to: .service(name: service.name, type: service.type, domain: service.domain, interface: nil), using: .tcp)
                self.connectToRemoteServer(server, connection: connection, completion: finish(_:))
            }
        }
    }
}

private extension ServerManager
{
    func addDiscoveredServer(_ server: Server)
    {
        var server = server
        server.isPreferred = (server.identifier == UserDefaults.standard.preferredServerID)
        
        guard !self.discoveredServers.contains(server) else { return }
        
        self.discoveredServers.append(server)
    }
    
    func makeListener() -> NWListener
    {
        let listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: ALTDeviceListeningSocket)!)
        listener.newConnectionHandler = { [weak self] (connection) in
            self?.incomingConnections?.append(connection)
            self?.incomingConnectionsSemaphore?.signal()
        }
        listener.stateUpdateHandler = { (state) in
            switch state
            {
            case .ready: break
            case .waiting, .setup: print("Listener socket waiting...")
            case .cancelled: print("Listener socket cancelled.")
            case .failed(let error): print("Listener socket failed:", error)
            @unknown default: break
            }
        }
        
        return listener
    }
    
    func startListeningForWiredConnections()
    {
        self.incomingConnections = []
        self.incomingConnectionsSemaphore = DispatchSemaphore(value: 0)
        
        self.connectionListener = self.makeListener()
        self.connectionListener?.start(queue: self.dispatchQueue)
    }
    
    func stopListeningForWiredConnection()
    {
        self.connectionListener?.cancel()
        self.connectionListener = nil
        
        self.incomingConnections = nil
        self.incomingConnectionsSemaphore = nil
    }
    
    func connectToRemoteServer(_ server: Server, connection: NWConnection, completion: @escaping (Result<Connection, Error>) -> Void)
    {
        connection.stateUpdateHandler = { [unowned connection] (state) in
            switch state
            {
            case .failed(let error):
                print("Failed to connect to service \(server.service?.name ?? "").", error)
                completion(.failure(ConnectionError.connectionFailed))
                
            case .cancelled:
                completion(.failure(OperationError.cancelled))
                
            case .ready:
                let connection = NetworkConnection(connection)
                completion(.success(connection))
                
            case .waiting: break
            case .setup: break
            case .preparing: break
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func connectToLocalServer(_ server: Server, completion: @escaping (Result<Connection, Error>) -> Void)
    {
        guard let machServiceName = server.machServiceName else { return completion(.failure(ConnectionError.connectionFailed)) }
        
        let xpcConnection = NSXPCConnection.makeConnection(machServiceName: machServiceName)
        
        let connection = XPCConnection(xpcConnection)
        connection.connect { (result) in
            switch result
            {
            case .failure(let error):
                print("Could not connect to AltDaemon XPC service \(machServiceName).", error)
                completion(.failure(error))
                
            case .success: completion(.success(connection))
            }
        }
    }
}

extension ServerManager: NetServiceBrowserDelegate
{
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser)
    {
        print("Discovering servers...")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser)
    {
        print("Stopped discovering servers.")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber])
    {
        print("Failed to discovering servers.", errorDict)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool)
    {
        service.delegate = self
        
        if let txtData = service.txtRecordData(), let server = Server(service: service, txtData: txtData)
        {
            self.addDiscoveredServer(server)
        }
        else
        {
            service.resolve(withTimeout: 3)
            self.services.insert(service)
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool)
    {
        if let index = self.discoveredServers.firstIndex(where: { $0.service == service })
        {
            self.discoveredServers.remove(at: index)
        }
        
        self.services.remove(service)
    }
}

extension ServerManager: NetServiceDelegate
{
    func netServiceDidResolveAddress(_ service: NetService)
    {
        guard let data = service.txtRecordData(), let server = Server(service: service, txtData: data) else { return }
        self.addDiscoveredServer(server)
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber])
    {
        print("Error resolving net service \(sender).", errorDict)
    }
    
    func netService(_ sender: NetService, didUpdateTXTRecord data: Data)
    {
        let txtDict = NetService.dictionary(fromTXTRecord: data)
        print("Service \(sender) updated TXT Record:", txtDict)
    }
}
