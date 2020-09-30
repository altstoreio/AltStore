//
//  XPCConnectionHandler.swift
//  AltDaemon
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Security

class XPCConnectionHandler: NSObject, ConnectionHandler
{
    var connectionHandler: ((Connection) -> Void)?
    var disconnectionHandler: ((Connection) -> Void)?
    
    private let dispatchQueue = DispatchQueue(label: "io.altstore.XPCConnectionListener", qos: .utility)
    private let listeners = XPCConnection.machServiceNames.map { NSXPCListener.makeListener(machServiceName: $0) }
    
    deinit
    {
        self.stopListening()
    }
        
    func startListening()
    {
        for listener in self.listeners
        {
            listener.delegate = self
            listener.resume()
        }
    }
    
    func stopListening()
    {
        self.listeners.forEach { $0.suspend() }
    }
}

private extension XPCConnectionHandler
{
    func disconnect(_ connection: Connection)
    {
        connection.disconnect()
        
        self.disconnectionHandler?(connection)
    }
}

extension XPCConnectionHandler: NSXPCListenerDelegate
{
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool
    {
        let maximumPathLength = 4 * UInt32(MAXPATHLEN)
        
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maximumPathLength))
        defer { pathBuffer.deallocate() }
        
        proc_pidpath(newConnection.processIdentifier, pathBuffer, maximumPathLength)
        
        let path = String(cString: pathBuffer)
        let fileURL = URL(fileURLWithPath: path)
                
        var code: UnsafeMutableRawPointer?
        defer { code.map { Unmanaged<AnyObject>.fromOpaque($0).release() } }
        
        var status = SecStaticCodeCreateWithPath(fileURL as CFURL, 0, &code)
        guard status == 0 else { return false }
        
        var signingInfo: CFDictionary?
        defer { signingInfo.map { Unmanaged<AnyObject>.passUnretained($0).release() } }
        
        status = SecCodeCopySigningInformation(code, kSecCSInternalInformation | kSecCSSigningInformation, &signingInfo)
        guard status == 0 else { return false }
        
        // Only accept connections from AltStore.
        guard
            let codeSigningInfo = signingInfo as? [String: Any],
            let bundleIdentifier = codeSigningInfo["identifier"] as? String,
            bundleIdentifier.contains("com.rileytestut.AltStore")
        else { return false }
        
        let connection = XPCConnection(newConnection)
        newConnection.invalidationHandler = { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            self.disconnect(connection)
        }

        self.connectionHandler?(connection)
        
        return true
    }
}
