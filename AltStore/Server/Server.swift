//
//  Server.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Network

import AltKit

extension ALTServerError
{
    init<E: Error>(_ error: E)
    {
        switch error
        {
        case let error as ALTServerError: self = error
        case is DecodingError: self = ALTServerError(.invalidResponse)
        case is EncodingError: self = ALTServerError(.invalidRequest)
        default:
            assertionFailure("Caught unknown error type")
            self = ALTServerError(.unknown)
        }
    }
}

enum ConnectionError: LocalizedError
{
    case serverNotFound
    case connectionFailed
    case connectionDropped
    
    var errorDescription: String? {
        switch self
        {
        case .serverNotFound: return NSLocalizedString("Could not find AltServer.", comment: "")
        case .connectionFailed: return NSLocalizedString("Could not connect to AltServer.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        }
    }
}

struct Server: Equatable
{
    var identifier: String
    var service: NetService
    
    var isPreferred = false
    
    init?(service: NetService, txtData: Data)
    {        
        let txtDictionary = NetService.dictionary(fromTXTRecord: txtData)
        guard let identifierData = txtDictionary["serverID"], let identifier = String(data: identifierData, encoding: .utf8) else { return nil }
        
        self.identifier = identifier
        self.service = service
    }
    
    func send<T: Encodable>(_ payload: T, via connection: NWConnection, prependSize: Bool = true, completionHandler: @escaping (Result<Void, Error>) -> Void)
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
                
                connection.send(content: requestSizeData, completion: .contentProcessed { (error) in
                    guard process(error) else { return }
                    
                    connection.send(content: data, completion: .contentProcessed { (error) in
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
    
    func receiveResponse(from connection: NWConnection, completionHandler: @escaping (Result<ServerResponse, Error>) -> Void)
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

private extension Server
{
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
