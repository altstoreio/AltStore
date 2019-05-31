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
        listener.service = NWListener.Service(type: ALTServerServiceType)
        
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
        
        func finish(error: ALTServerError?)
        {
            if let error = error
            {
                print("Failed to process request from \(connection.endpoint).", error)
            }
            else
            {
                print("Processed request from \(connection.endpoint).")
            }
            
            let success = (error == nil)
            let response = ServerResponse(success: success, error: error)
            
            self.send(response, to: connection) { (result) in
                print("Sent response to \(connection) with result:", result)
                
                self.disconnect(connection)
            }
        }
        
        self.receiveRequest(from: connection) { (result) in
            switch result
            {
            case .failure(let error): finish(error: error)
            case .success(let request, let fileURL):
                ALTDeviceManager.shared.installApp(at: fileURL, toDeviceWithUDID: request.udid) { (success, error) in
                    let error = error.map { $0 as? ALTServerError ?? ALTServerError(.unknown) }
                    finish(error: error)
                }
            }
        }
    }
    
    func receiveRequest(from connection: NWConnection, completionHandler: @escaping (Result<(ServerRequest, URL), ALTServerError>) -> Void)
    {
        let size = MemoryLayout<Int32>.size
        
        connection.receive(minimumIncompleteLength: size, maximumLength: size) { (data, _, _, error) in
            do
            {
                let data = try self.process(data: data, error: error, from: connection)
                
                let expectedBytes = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                connection.receive(minimumIncompleteLength: expectedBytes, maximumLength: expectedBytes) { (data, _, _, error) in
                    do
                    {
                        let data = try self.process(data: data, error: error, from: connection)
                        
                        let request = try JSONDecoder().decode(ServerRequest.self, from: data)
                        self.process(request, from: connection, completionHandler: completionHandler)
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
    
    func process(_ request: ServerRequest, from connection: NWConnection, completionHandler: @escaping (Result<(ServerRequest, URL), ALTServerError>) -> Void)
    {
        connection.receive(minimumIncompleteLength: request.contentSize, maximumLength: request.contentSize) { (data, _, _, error) in
            do
            {
                let data = try self.process(data: data, error: error, from: connection)
                
                guard ALTDeviceManager.shared.connectedDevices.contains(where: { $0.identifier == request.udid }) else { throw ALTServerError(.deviceNotFound) }
                
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                try data.write(to: temporaryURL, options: .atomic)
                
                print("Wrote app to URL:", temporaryURL)
                
                completionHandler(.success((request, temporaryURL)))
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }

    func send(_ response: ServerResponse, to connection: NWConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
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
}
