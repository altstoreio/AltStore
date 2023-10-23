//
//  ServerConnection.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltStoreCore

class ServerConnection
{
    var server: Server
    var connection: Connection
    
    init(server: Server, connection: Connection)
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
            
            func process<T>(_ result: Result<T, ALTServerError>) -> Bool
            {
                switch result
                {
                case .success: return true
                case .failure(let error):
                    completionHandler(.failure(error))
                    return false
                }
            }
            
            if prependSize
            {
                let requestSize = Int32(data.count)
                let requestSizeData = withUnsafeBytes(of: requestSize) { Data($0) }
                
                self.connection.send(requestSizeData) { (result) in
                    guard process(result) else { return }
                    
                    self.connection.send(data) { (result) in
                        guard process(result) else { return }
                        completionHandler(.success(()))
                    }
                }
            }
            else
            {
                self.connection.send(data) { (result) in
                    guard process(result) else { return }
                    completionHandler(.success(()))
                }
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
        
        self.connection.receiveData(expectedSize: size) { (result) in
            do
            {
                let data = try result.get()
                
                let expectedBytes = Int(data.withUnsafeBytes { $0.load(as: Int32.self) })
                self.connection.receiveData(expectedSize: expectedBytes) { (result) in
                    do
                    {
                        let data = try result.get()
                        
                        let response = try AltStoreCore.JSONDecoder().decode(ServerResponse.self, from: data)
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
