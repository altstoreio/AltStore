//
//  ConnectionManager.swift
//  AltServer
//
//  Created by Riley Testut on 5/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network
import AppKit

import AltKit

extension ALTServerError
{
    init<E: Error>(_ error: E)
    {
        switch error
        {
        case let error as ALTServerError: self = error
        case is DecodingError: self = ALTServerError(.invalidRequest)
        case is EncodingError: self = ALTServerError(.invalidResponse)
        case let error as NSError:
            self = ALTServerError(.unknown, userInfo: error.userInfo)
        }
    }
}

extension ConnectionManager
{
    enum State
    {
        case notRunning
        case connecting
        case running(NWListener.Service)
        case failed(Swift.Error)
    }
}

class ConnectionManager
{
    static let shared = ConnectionManager()
    
    var stateUpdateHandler: ((State) -> Void)?
    
    private(set) var state: State = .notRunning {
        didSet {
            self.stateUpdateHandler?(self.state)
        }
    }
    
    private lazy var listener = self.makeListener()
    private let dispatchQueue = DispatchQueue(label: "com.rileytestut.AltServer.connections", qos: .utility)
    
    private var connections = [ClientConnection]()
    private var notificationConnections = [ALTDevice: NotificationConnection]()
    
    private init()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(ConnectionManager.deviceDidConnect(_:)), name: .deviceManagerDeviceDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ConnectionManager.deviceDidDisconnect(_:)), name: .deviceManagerDeviceDidDisconnect, object: nil)
    }
    
    func start()
    {
        switch self.state
        {
        case .notRunning, .failed: self.listener.start(queue: self.dispatchQueue)
        default: break
        }
    }
    
    func stop()
    {
        switch self.state
        {
        case .running: self.listener.cancel()
        default: break
        }
    }
    
    func disconnect(_ connection: ClientConnection)
    {
        connection.disconnect()
        
        if let index = self.connections.firstIndex(where: { $0 === connection })
        {
            self.connections.remove(at: index)
        }
    }
}

private extension ConnectionManager
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
            case .failed(let error):
                self.state = .failed(error)
                self.start()
                
            @unknown default: break
            }
        }
        
        listener.newConnectionHandler = { [weak self] (connection) in
            self?.prepare(connection)
        }
        
        return listener
    }
    
    func prepare(_ connection: NWConnection)
    {
        let clientConnection = ClientConnection(connection: .wireless(connection))
        
        guard !self.connections.contains(where: { $0 === clientConnection }) else { return }
        self.connections.append(clientConnection)
        
        connection.stateUpdateHandler = { [weak self] (state) in
            switch state
            {
            case .setup, .preparing: break
                
            case .ready:
                print("Connected to client:", connection.endpoint)
                self?.handleRequest(for: clientConnection)
                
            case .waiting:
                print("Waiting for connection...")
                
            case .failed(let error):
                print("Failed to connect to service \(connection.endpoint).", error)
                self?.disconnect(clientConnection)
                
            case .cancelled:
                self?.disconnect(clientConnection)
                
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
}

private extension ConnectionManager
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
                    
                    let clientConnection = ClientConnection(connection: .wired(wiredConnection))
                    self.handleRequest(for: clientConnection)
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

private extension ConnectionManager
{
    func handleRequest(for connection: ClientConnection)
    {
        connection.receiveRequest() { (result) in
            print("Received initial request with result:", result)
            
            switch result
            {
            case .failure(let error):
                let response = ErrorResponse(error: ALTServerError(error))
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent error response with result:", result)
                }
                
            case .success(.anisetteData(let request)):
                self.handleAnisetteDataRequest(request, for: connection)
                
            case .success(.prepareApp(let request)):
                self.handlePrepareAppRequest(request, for: connection)
                
            case .success(.beginInstallation): break
                
            case .success(.installProvisioningProfiles(let request)):
                self.handleInstallProvisioningProfilesRequest(request, for: connection)
                
            case .success(.removeProvisioningProfiles(let request)):
                self.handleRemoveProvisioningProfilesRequest(request, for: connection)
                
            case .success(.unknown):
                let response = ErrorResponse(error: ALTServerError(.unknownRequest))
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent unknown request response with result:", result)
                }
            }
        }
    }
    
    func handleAnisetteDataRequest(_ request: AnisetteDataRequest, for connection: ClientConnection)
    {
        AnisetteDataManager.shared.requestAnisetteData { (result) in
            switch result
            {
            case .failure(let error):
                let errorResponse = ErrorResponse(error: ALTServerError(error))
                connection.send(errorResponse, shouldDisconnect: true) { (result) in
                    print("Sent anisette data error response with result:", result)
                }
                
            case .success(let anisetteData):
                let response = AnisetteDataResponse(anisetteData: anisetteData)
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent anisette data response with result:", result)
                }
            }
        }
    }
    
    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: ClientConnection)
    {
        var temporaryURL: URL?
        
        func finish(_ result: Result<Void, ALTServerError>)
        {
            if let temporaryURL = temporaryURL
            {
                do { try FileManager.default.removeItem(at: temporaryURL) }
                catch { print("Failed to remove .ipa.", error) }
            }
            
            switch result
            {
            case .failure(let error):
                print("Failed to process request from \(connection).", error)
                
                let response = ErrorResponse(error: ALTServerError(error))
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent install app error response to \(connection) with result:", result)
                }
                
            case .success:
                print("Processed request from \(connection).")
                
                let response = InstallationProgressResponse(progress: 1.0)
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent install app response to \(connection) with result:", result)
                }
            }
        }
        
        self.receiveApp(for: request, from: connection) { (result) in
            print("Received app with result:", result)
            
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success(let fileURL):
                temporaryURL = fileURL
                
                print("Awaiting begin installation request...")
                
                connection.receiveRequest() { (result) in
                    print("Received begin installation request with result:", result)
                    
                    switch result
                    {
                    case .failure(let error): finish(.failure(error))
                    case .success(.beginInstallation(let installRequest)):
                        print("Installing to device \(request.udid)...")
                        
                        self.installApp(at: fileURL, toDeviceWithUDID: request.udid, activeProvisioningProfiles: installRequest.activeProfiles, connection: connection) { (result) in
                            print("Installed to device with result:", result)
                            switch result
                            {
                            case .failure(let error): finish(.failure(error))
                            case .success: finish(.success(()))
                            }
                        }
                        
                    case .success:
                        let response = ErrorResponse(error: ALTServerError(.unknownRequest))
                        connection.send(response, shouldDisconnect: true) { (result) in
                            print("Sent unknown request error response to \(connection) with result:", result)
                        }
                    }
                }
            }
        }
    }
    
    func receiveApp(for request: PrepareAppRequest, from connection: ClientConnection, completionHandler: @escaping (Result<URL, ALTServerError>) -> Void)
    {
        connection.receiveData(expectedBytes: request.contentSize) { (result) in
            do
            {
                print("Received app data!")
                
                let data = try result.get()
                                
                guard ALTDeviceManager.shared.availableDevices.contains(where: { $0.identifier == request.udid }) else { throw ALTServerError(.deviceNotFound) }
                
                print("Writing app data...")
                
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                try data.write(to: temporaryURL, options: .atomic)
                
                print("Wrote app to URL:", temporaryURL)
                
                completionHandler(.success(temporaryURL))
            }
            catch
            {
                print("Error processing app data:", error)
                
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
    
    func installApp(at fileURL: URL, toDeviceWithUDID udid: String, activeProvisioningProfiles: Set<String>?, connection: ClientConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        let serialQueue = DispatchQueue(label: "com.altstore.ConnectionManager.installQueue", qos: .default)
        var isSending = false
        
        var observation: NSKeyValueObservation?
        
        let progress = ALTDeviceManager.shared.installApp(at: fileURL, toDeviceWithUDID: udid, activeProvisioningProfiles: activeProvisioningProfiles) { (success, error) in
            print("Installed app with result:", error == nil ? "Success" : error!.localizedDescription)
            
            if let error = error.map({ $0 as? ALTServerError ?? ALTServerError(.unknown) })
            {
                completionHandler(.failure(error))
            }
            else
            {
                completionHandler(.success(()))
            }
            
            observation?.invalidate()
            observation = nil
        }
        
        observation = progress.observe(\.fractionCompleted, changeHandler: { (progress, change) in
            serialQueue.async {
                guard !isSending else { return }
                isSending = true
                
                print("Progress:", progress.fractionCompleted)
                let response = InstallationProgressResponse(progress: progress.fractionCompleted)
                
                connection.send(response) { (result) in                    
                    serialQueue.async {
                        isSending = false
                    }
                }
            }
        })
    }
    
    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for connection: ClientConnection)
    {
        let removeInactiveProfiles = (request.activeProfiles != nil)
        ALTDeviceManager.shared.installProvisioningProfiles(request.provisioningProfiles, toDeviceWithUDID: request.udid, activeProvisioningProfiles: request.activeProfiles, removeInactiveProvisioningProfiles: removeInactiveProfiles) { (errors) in
            
            if let error = errors.values.first
            {
                print("Failed to install profiles \(request.provisioningProfiles.map { $0.bundleIdentifier }):", errors)
                
                let errorResponse = ErrorResponse(error: ALTServerError(error))
                connection.send(errorResponse, shouldDisconnect: true) { (result) in
                    print("Sent install profiles error response with result:", result)
                }
            }
            else
            {
                print("Installed profiles:", request.provisioningProfiles.map { $0.bundleIdentifier })
                
                let response = InstallProvisioningProfilesResponse()
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent install profiles response to \(connection) with result:", result)
                }
            }
        }
    }
    
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: ClientConnection)
    {
        ALTDeviceManager.shared.removeProvisioningProfiles(forBundleIdentifiers: request.bundleIdentifiers, fromDeviceWithUDID: request.udid) { (errors) in
            if let error = errors.values.first
            {
                print("Failed to remove profiles \(request.bundleIdentifiers):", errors)
                
                let errorResponse = ErrorResponse(error: ALTServerError(error))
                connection.send(errorResponse, shouldDisconnect: true) { (result) in
                    print("Sent remove profiles error response with result:", result)
                }
            }
            else
            {
                print("Removed profiles:", request.bundleIdentifiers)
                
                let response = RemoveProvisioningProfilesResponse()
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent remove profiles error response to \(connection) with result:", result)
                }
            }
        }
    }
}

private extension ConnectionManager
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
