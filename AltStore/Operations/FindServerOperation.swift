//
//  FindServerOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/8/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltKit
import Roxas

private extension Notification.Name
{
    static let didReceiveWiredServerConnectionResponse = Notification.Name("io.altstore.didReceiveWiredServerConnectionResponse")
}

private let ReceivedWiredServerConnectionResponse: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void =
{ (center, observer, name, object, userInfo) in
    NotificationCenter.default.post(name: .didReceiveWiredServerConnectionResponse, object: nil)
}

@objc(FindServerOperation)
class FindServerOperation: ResultOperation<Server>
{
    let group: OperationGroup
    
    private var isWiredServerConnectionAvailable = false
        
    init(group: OperationGroup)
    {
        self.group = group
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.group.error
        {
            self.finish(.failure(error))
            return
        }
        
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        
        // Prepare observers to receive callback from wired server (if connected).
        CFNotificationCenterAddObserver(notificationCenter, nil, ReceivedWiredServerConnectionResponse, CFNotificationName.wiredServerConnectionAvailableResponse.rawValue, nil, .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(FindServerOperation.didReceiveWiredServerConnectionResponse(_:)), name: .didReceiveWiredServerConnectionResponse, object: nil)
        
        // Post notification.
        CFNotificationCenterPostNotification(notificationCenter, .wiredServerConnectionAvailableRequest, nil, nil, true)
        
        // Wait for either callback or timeout.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if self.isWiredServerConnectionAvailable
            {
                let server = Server(isWiredConnection: true)
                self.finish(.success(server))
            }
            else
            {
                if let server = ServerManager.shared.discoveredServers.first(where: { $0.isPreferred })
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
    }
}

private extension FindServerOperation
{
    @objc func didReceiveWiredServerConnectionResponse(_ notification: Notification)
    {
        self.isWiredServerConnectionAvailable = true
    }
}

