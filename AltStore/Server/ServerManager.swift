//
//  ServerManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit

class ServerManager: NSObject
{
    static let shared = ServerManager()
    
    private(set) var isDiscovering = false
    private(set) var discoveredServers = [Server]()
    
    private let serviceBrowser = NetServiceBrowser()
    
    private var services = Set<NetService>()
    
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
    }
    
    func stopDiscovering()
    {
        guard self.isDiscovering else { return }
        self.isDiscovering = false
        
        self.discoveredServers.removeAll()
        self.services.removeAll()
        self.serviceBrowser.stop()
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
