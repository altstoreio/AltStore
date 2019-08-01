//
//  ConnectionManager.swift
//  AltServer
//
//  Created by Riley Testut on 5/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

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
        default:
            assertionFailure("Caught unknown error type")
            self = ALTServerError(.unknown)
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
    
    private var connections = [NWConnection]()
    
    private init()
    {
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
            self?.awaitRequest(from: connection)
        }
        
        return listener
    }
    
    func disconnect(_ connection: NWConnection)
    {
        switch connection.state
        {
        case .cancelled, .failed:
            print("Disconnecting from \(connection.endpoint)...")
            
            if let index = self.connections.firstIndex(where: { $0 === connection })
            {
                self.connections.remove(at: index)
            }
            
        default:
            // State update handler will call this method again.
            connection.cancel()
        }
    }
    
    func process(data: Data?, error: NWError?, from connection: NWConnection) throws -> Data
    {
        do
        {
            do
            {
                guard let data = data else { throw error ?? ALTServerError(.unknown) }
                return data
            }
            catch let error as NWError
            {
                print("Error receiving data from connection \(connection)", error)
                
                throw ALTServerError(.lostConnection)
            }
            catch
            {
                throw error
            }
        }
        catch let error as ALTServerError
        {
            throw error
        }
        catch
        {
            preconditionFailure("A non-ALTServerError should never be thrown from this method.")
        }
    }
}

private extension ConnectionManager
{
    func awaitRequest(from connection: NWConnection)
    {
        guard !self.connections.contains(where: { $0 === connection }) else { return }
        self.connections.append(connection)
        
        
        connection.stateUpdateHandler = { [weak self] (state) in
            switch state
            {
            case .setup, .preparing: break
                
            case .ready:
                print("Connected to client:", connection.endpoint)
                
                self?.receiveApp(from: connection) { (result) in
                    self?.finish(connection: connection, error: result.error)
                }
                
            case .waiting:
                print("Waiting for connection...")
                
            case .failed(let error):
                print("Failed to connect to service \(connection.endpoint).", error)
                self?.disconnect(connection)
                
            case .cancelled:
                self?.disconnect(connection)
                
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func receiveApp(from connection: NWConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        self.receive(PrepareAppRequest.self, from: connection) { (result) in
            print("Received request with result:", result)
            
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let request):
                self.receiveApp(for: request, from: connection) { (result) in
                    print("Received app with result:", result)
                    
                    switch result
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success(let request, let fileURL):
                        print("Awaiting begin installation request...")
                        
                        self.receive(BeginInstallationRequest.self, from: connection) { (result) in
                            print("Received begin installation request with result:", result)
                            
                            switch result
                            {
                            case .failure(let error): completionHandler(.failure(error))
                            case .success:
                                print("Installing to device \(request.udid)...")
                                
                                self.installApp(at: fileURL, toDeviceWithUDID: request.udid, connection: connection) { (result) in
                                    print("Installed to device with result:", result)
                                    switch result
                                    {
                                    case .failure(let error): completionHandler(.failure(error))
                                    case .success: completionHandler(.success(()))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func finish(connection: NWConnection, error: ALTServerError?)
    {
        if let error = error
        {
            print("Failed to process request from \(connection.endpoint).", error)
        }
        else
        {
            print("Processed request from \(connection.endpoint).")
        }
        
        let response = ServerResponse(progress: 1.0, error: error)
        
        self.send(response, to: connection) { (result) in
            print("Sent response to \(connection.endpoint) with result:", result)
            
            self.disconnect(connection)
        }
    }
    
    func receiveApp(for request: PrepareAppRequest, from connection: NWConnection, completionHandler: @escaping (Result<(PrepareAppRequest, URL), ALTServerError>) -> Void)
    {
        connection.receive(minimumIncompleteLength: request.contentSize, maximumLength: request.contentSize) { (data, _, _, error) in
            do
            {
                print("Received app data!")
                
                let data = try self.process(data: data, error: error, from: connection)
                
                print("Processed app data!")
                
                guard ALTDeviceManager.shared.availableDevices.contains(where: { $0.identifier == request.udid }) else { throw ALTServerError(.deviceNotFound) }
                
                print("Writing app data...")
                
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                try data.write(to: temporaryURL, options: .atomic)
                
                print("Wrote app to URL:", temporaryURL)
                
                completionHandler(.success((request, temporaryURL)))
            }
            catch
            {
                print("Error processing app data:", error)
                
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
    
    func installApp(at fileURL: URL, toDeviceWithUDID udid: String, connection: NWConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        let serialQueue = DispatchQueue(label: "com.altstore.ConnectionManager.installQueue", qos: .default)
        var isSending = false
        
        var observation: NSKeyValueObservation?
        
        let progress = ALTDeviceManager.shared.installApp(at: fileURL, toDeviceWithUDID: udid) { (success, error) in
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
                let response = ServerResponse(progress: progress.fractionCompleted, error: nil)
                
                self.send(response, to: connection) { (result) in                    
                    serialQueue.async {
                        isSending = false
                    }
                }
            }
        })
    }

    func send<T: Encodable>(_ response: T, to connection: NWConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        do
        {            
            let data = try JSONEncoder().encode(response)
            let responseSize = withUnsafeBytes(of: Int32(data.count)) { Data($0) }

            connection.send(content: responseSize, completion: .contentProcessed { (error) in
                do
                {
                    if let error = error
                    {
                        throw error
                    }

                    connection.send(content: data, completion: .contentProcessed { (error) in
                        if error != nil
                        {
                            completionHandler(.failure(.init(.lostConnection)))
                        }
                        else
                        {
                            completionHandler(.success(()))
                        }
                    })
                }
                catch
                {
                    completionHandler(.failure(.init(.lostConnection)))
                }
            })
        }
        catch
        {
            completionHandler(.failure(.init(.invalidResponse)))
        }
    }
    
    func receive<T: Decodable>(_ responseType: T.Type, from connection: NWConnection, completionHandler: @escaping (Result<T, ALTServerError>) -> Void)
    {
        let size = MemoryLayout<Int32>.size
        
        print("Receiving request size")
        connection.receive(minimumIncompleteLength: size, maximumLength: size) { (data, _, _, error) in
            do
            {
                let data = try self.process(data: data, error: error, from: connection)
                
                print("Receiving request...")
                
                let expectedBytes = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                connection.receive(minimumIncompleteLength: expectedBytes, maximumLength: expectedBytes) { (data, _, _, error) in
                    do
                    {
                        let data = try self.process(data: data, error: error, from: connection)
                        
                        let request = try JSONDecoder().decode(T.self, from: data)
                        
                        print("Received installation request:", request)
                        
                        completionHandler(.success(request))
                    }
                    catch
                    {
                        completionHandler(.failure(ALTServerError(error)))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
}
