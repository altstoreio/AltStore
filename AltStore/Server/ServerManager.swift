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
        self.serviceBrowser.stop()
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
        let server = Server(service: service)
        guard !self.discoveredServers.contains(server) else { return }
        
        self.discoveredServers.append(server)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool)
    {
        let server = Server(service: service)
        
        if let index = self.discoveredServers.firstIndex(of: server)
        {
            self.discoveredServers.remove(at: index)
        }
    }
}
