//
//  Server.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
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

enum InstallError: Error
{
    case unknown
    case cancelled
    case invalidApp
    case noUDID
    case server(ALTServerError)
}

struct Server: Equatable
{
    var service: NetService
    
    private let dispatchQueue = DispatchQueue(label: "com.rileytestut.AltStore.server", qos: .utility)
    
    func installApp(at fileURL: URL, identifier: String, completionHandler: @escaping (Result<Void, InstallError>) -> Void)
    {
        var isFinished = false
        
        var serverConnection: NWConnection?
        
        func finish(error: InstallError?)
        {
            // Prevent duplicate callbacks if connection is lost.
            guard !isFinished else { return }
            isFinished = true
            
            if let connection = serverConnection
            {
                connection.cancel()
            }
            
            if let error = error
            {
                print("Failed to install \(identifier).", error)
                completionHandler(.failure(error))
            }
            else
            {
                print("Installed \(identifier)!")
                completionHandler(.success(()))
            }
        }        
        
        self.connect { (result) in
            switch result
            {
            case .failure(let error): finish(error: error)
            case .success(let connection):
                serverConnection = connection
                
                self.sendApp(at: fileURL, via: connection) { (result) in
                    switch result
                    {
                    case .failure(let error): finish(error: error)
                    case .success:
                        
                        self.receiveResponse(from: connection) { (result) in
                            switch result
                            {
                            case .success: finish(error: nil)
                            case .failure(let error): finish(error: .server(error))
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension Server
{
    func connect(completionHandler: @escaping (Result<NWConnection, InstallError>) -> Void)
    {
        let connection = NWConnection(to: .service(name: self.service.name, type: self.service.type, domain: self.service.domain, interface: nil), using: .tcp)
        
        connection.stateUpdateHandler = { [weak service, unowned connection] (state) in
            switch state
            {
            case .ready: completionHandler(.success(connection))
            case .cancelled: completionHandler(.failure(.cancelled))
                
            case .failed(let error):
                print("Failed to connect to service \(service?.name ?? "").", error)
                completionHandler(.failure(.server(.init(.connectionFailed))))
                
            case .waiting: break
            case .setup: break
            case .preparing: break
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func sendApp(at fileURL: URL, via connection: NWConnection, completionHandler: @escaping (Result<Void, InstallError>) -> Void)
    {
        do
        {
            guard let appData = try? Data(contentsOf: fileURL) else { throw InstallError.invalidApp }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw InstallError.noUDID }
            
            let request = ServerRequest(udid: udid, contentSize: appData.count)
            let requestData = try JSONEncoder().encode(request)
            
            let requestSize = Int32(requestData.count)
            let requestSizeData = withUnsafeBytes(of: requestSize) { Data($0) }
            
            // Send request data size.
            print("Sending request data size \(requestSize)")
            connection.send(content: requestSizeData, completion: .contentProcessed { (error) in
                if error != nil
                {
                    completionHandler(.failure(.server(.init(.lostConnection))))
                }
                else
                {
                    // Send request.
                    print("Sending request \(request)")
                    connection.send(content: requestData, completion: .contentProcessed { (error) in
                        if error != nil
                        {
                            completionHandler(.failure(.server(.init(.lostConnection))))
                        }
                        else
                        {
                            // Send app data.
                            print("Sending app data (Size: \(appData.count))")
                            connection.send(content: appData, completion: .contentProcessed { (error) in
                                if error != nil
                                {
                                    completionHandler(.failure(.server(.init(.lostConnection))))
                                }
                                else
                                {
                                    completionHandler(.success(()))
                                }
                            })
                        }
                    })
                }
            })
        }
        catch is EncodingError
        {
            completionHandler(.failure(.server(.init(.invalidRequest))))
        }
        catch let error as InstallError
        {
            completionHandler(.failure(error))
        }
        catch
        {
            assertionFailure("Unknown error type. \(error)")
            completionHandler(.failure(.unknown))
        }
    }
    
    func receiveResponse(from connection: NWConnection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
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
                        
                        if let error = response.error
                        {
                            completionHandler(.failure(error))
                        }
                        else
                        {
                            completionHandler(.success(()))
                        }
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
