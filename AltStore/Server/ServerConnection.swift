//
//  ServerConnection.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltKit

class ServerConnection
{
    var server: Server
    var connection: NWConnection
    
    init(server: Server, connection: NWConnection)
    {
        self.server = server
        self.connection = connection
    }
    
    func send<T: Encodable>(_ payload: T, prependSize: Bool = true, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            let data: Data
            
            if let payload = payload as? Data
            {
                data = payload
            }
            else
            {
                data = try JSONEncoder().encode(payload)
            }
            
            func process(_ error: Error?) -> Bool
            {
                if error != nil
                {
                    completionHandler(.failure(ConnectionError.connectionDropped))
                    return false
                }
                else
                {
                    return true
                }
            }
            
            if prependSize
            {
                let requestSize = Int32(data.count)
                let requestSizeData = withUnsafeBytes(of: requestSize) { Data($0) }
                
                self.connection.send(content: requestSizeData, completion: .contentProcessed { (error) in
                    guard process(error) else { return }
                    
                    self.connection.send(content: data, completion: .contentProcessed { (error) in
                        guard process(error) else { return }
                        completionHandler(.success(()))
                    })
                })
                
            }
            else
            {
                connection.send(content: data, completion: .contentProcessed { (error) in
                    guard process(error) else { return }
                    completionHandler(.success(()))
                })
            }
        }
        catch
        {
            print("Invalid request.", error)
            completionHandler(.failure(ALTServerError(.invalidRequest)))
        }
    }
    
    func receiveResponse(completionHandler: @escaping (Result<ServerResponse, Error>) -> Void)
    {
        let size = MemoryLayout<Int32>.size
        
        self.connection.receive(minimumIncompleteLength: size, maximumLength: size) { (data, _, _, error) in
            do
            {
                let data = try self.process(data: data, error: error)
                
                let expectedBytes = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                self.connection.receive(minimumIncompleteLength: expectedBytes, maximumLength: expectedBytes) { (data, _, _, error) in
                    do
                    {
                        let data = try self.process(data: data, error: error)
                        
                        let response = try JSONDecoder().decode(ServerResponse.self, from: data)
                        completionHandler(.success(response))
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

private extension ServerConnection
{
    func process(data: Data?, error: NWError?) throws -> Data
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
