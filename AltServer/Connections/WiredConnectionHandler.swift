//
//  WiredConnectionHandler.swift
//  AltServer
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

class WiredConnectionHandler: ConnectionHandler
{
    var connectionHandler: ((Connection) -> Void)?
    var disconnectionHandler: ((Connection) -> Void)?
    
    private var notificationConnections = [ALTDevice: NotificationConnection]()
    
    func startListening()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(WiredConnectionHandler.deviceDidConnect(_:)), name: .deviceManagerDeviceDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WiredConnectionHandler.deviceDidDisconnect(_:)), name: .deviceManagerDeviceDidDisconnect, object: nil)
    }
    
    func stopListening()
    {
        NotificationCenter.default.removeObserver(self, name: .deviceManagerDeviceDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .deviceManagerDeviceDidDisconnect, object: nil)
    }
}

private extension WiredConnectionHandler
{
    func startNotificationConnection(to device: ALTDevice)
    {
        ALTDeviceManager.shared.startNotificationConnection(to: device) { (connection, error) in
            guard let connection = connection else { return }

            let notifications: [CFNotificationName] = [.wiredServerConnectionAvailableRequest, .wiredServerConnectionStartRequest]
            connection.startListening(forNotifications: notifications.map { String($0.rawValue) }) { (success, error) in
                guard success else { return }

                connection.receivedNotificationHandler = { [weak self, weak connection] (notification) in
                    guard let self = self, let connection = connection else { return }
                    self.handle(notification, for: connection)
                }

                self.notificationConnections[device] = connection
            }
        }
    }

    func stopNotificationConnection(to device: ALTDevice)
    {
        guard let connection = self.notificationConnections[device] else { return }
        connection.disconnect()

        self.notificationConnections[device] = nil
    }

    func handle(_ notification: CFNotificationName, for connection: NotificationConnection)
    {
        switch notification
        {
        case .wiredServerConnectionAvailableRequest:
            connection.sendNotification(.wiredServerConnectionAvailableResponse) { (success, error) in
                if let error = error, !success
                {
                    print("Error sending wired server connection response.", error)
                }
                else
                {
                    print("Sent wired server connection available response!")
                }
            }

        case .wiredServerConnectionStartRequest:
            ALTDeviceManager.shared.startWiredConnection(to: connection.device) { (wiredConnection, error) in
                if let wiredConnection = wiredConnection
                {
                    print("Started wired server connection!")
                    self.connectionHandler?(wiredConnection)
                    
                    var observation: NSKeyValueObservation?
                    observation = wiredConnection.observe(\.isConnected) { [weak self] (connection, change) in
                        guard !connection.isConnected else { return }
                        self?.disconnectionHandler?(connection)
                        
                        observation?.invalidate()
                    }
                }
                else if let error = error
                {
                    print("Error starting wired server connection.", error)
                }
            }

        default: break
        }
    }
}

private extension WiredConnectionHandler
{
    @objc func deviceDidConnect(_ notification: Notification)
    {
        guard let device = notification.object as? ALTDevice else { return }
        self.startNotificationConnection(to: device)
    }

    @objc func deviceDidDisconnect(_ notification: Notification)
    {
        guard let device = notification.object as? ALTDevice else { return }
        self.stopNotificationConnection(to: device)
    }
}
