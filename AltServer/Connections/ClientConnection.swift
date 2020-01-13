//
//  ClientConnection.swift
//  AltServer
//
//  Created by Riley Testut on 1/9/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit
import AltSign

extension ClientConnection
{
    enum Connection
    {
        case wireless(NWConnection)
        case wired(WiredConnection)
    }
}

class ClientConnection
{
    let connection: Connection
    
    init(connection: Connection)
    {
        self.connection = connection
    }
    
    func disconnect()
    {
        switch self.connection
        {
        case .wireless(let connection):
            switch connection.state
            {
            case .cancelled, .failed:
                print("Disconnecting from \(connection.endpoint)...")
                
            default:
                // State update handler might call this method again.
                connection.cancel()
            }
            
        case .wired(let connection):
            connection.disconnect()
        }
    }
    
    func send<T: Encodable>(_ response: T, shouldDisconnect: Bool = false, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        func finish(_ result: Result<Void, ALTServerError>)
        {
            completionHandler(result)
            
            if shouldDisconnect
            {
                // Add short delay to prevent us from dropping connection too quickly.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    self.disconnect()
                }
            }
        }
        
        do
        {
            let data = try JSONEncoder().encode(response)
            let responseSize = withUnsafeBytes(of: Int32(data.count)) { Data($0) }
            
            self.send(responseSize) { (result) in
                switch result
                {
                case .failure: finish(.failure(.init(.lostConnection)))
                case .success:
                    
                    self.send(data) { (result) in
                        switch result
                        {
                        case .failure: finish(.failure(.init(.lostConnection)))
                        case .success: finish(.success(()))
                        }
                    }
                }
            }
        }
        catch
        {
            finish(.failure(.init(.invalidResponse)))
        }
    }
    
    func receiveRequest(completionHandler: @escaping (Result<ServerRequest, ALTServerError>) -> Void)
    {
        let size = MemoryLayout<Int32>.size
        
        print("Receiving request size")
        self.receiveData(expectedBytes: size) { (result) in
            do
            {
                let data = try result.get()
                
                print("Receiving request...")
                let expectedBytes = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                self.receiveData(expectedBytes: expectedBytes) { (result) in
                    do
                    {
                        let data = try result.get()
                        let request = try JSONDecoder().decode(ServerRequest.self, from: data)
                        
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
    
    func send(_ data: Data, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        switch self.connection
        {
        case .wireless(let connection):
            connection.send(content: data, completion: .contentProcessed { (error) in
                if let error = error
                {
                    completionHandler(.failure(error))
                }
                else
                {
                    completionHandler(.success(()))
                }
            })
            
        case .wired(let connection):
            connection.send(data) { (success, error) in
                if !success
                {
                    completionHandler(.failure(ALTServerError(.lostConnection)))
                }
                else
                {
                    completionHandler(.success(()))
                }
            }
        }
    }
    
    func receiveData(expectedBytes: Int, completionHandler: @escaping (Result<Data, Error>) -> Void)
    {
        func finish(data: Data?, error: Error?)
        {
            do
            {
                let data = try self.process(data: data, error: error)
                completionHandler(.success(data))
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
        
        switch self.connection
        {
        case .wireless(let connection):
            connection.receive(minimumIncompleteLength: expectedBytes, maximumLength: expectedBytes) { (data, _, _, error) in
                finish(data: data, error: error)
            }
            
        case .wired(let connection):
            connection.receiveData(withExpectedSize: expectedBytes) { (data, error) in
                finish(data: data, error: error)
            }
        }
    }
}

extension ClientConnection: CustomStringConvertible
{
    var description: String {
        switch self.connection
        {
        case .wireless(let connection): return "\(connection.endpoint) (Wireless)"
        case .wired(let connection): return "\(connection.device.name) (Wired)"
        }
    }
}

private extension ClientConnection
{
    func process(data: Data?, error: Error?) throws -> Data
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
