//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
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
        case is DecodingError: self = ALTServerError(.invalidResponse)
        case is EncodingError: self = ALTServerError(.invalidRequest)
        default:
            assertionFailure("Caught unknown error type")
            self = ALTServerError(.unknown)
        }
    }
}

enum InstallationError: LocalizedError
{
    case serverNotFound
    case connectionFailed
    case connectionDropped
    case invalidApp
    
    var errorDescription: String? {
        switch self
        {
        case .serverNotFound: return NSLocalizedString("Could not find AltServer.", comment: "")
        case .connectionFailed: return NSLocalizedString("Could not connect to AltServer.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        }
    }
}

@objc(InstallAppOperation)
class InstallAppOperation: ResultOperation<Void>
{
    var fileURL: URL?
    
    private let dispatchQueue = DispatchQueue(label: "com.altstore.InstallAppOperation")
    
    private var connection: NWConnection?
    
    override init()
    {
        super.init()
        
        self.progress.totalUnitCount = 4
    }
    
    override func main()
    {
        super.main()
        
        guard let fileURL = self.fileURL else { return self.finish(.failure(OperationError.appNotFound)) }
        
        // Connect to server.
        self.connect { (result) in
            switch result
            {
            case .failure(let error): self.finish(.failure(error))
            case .success(let connection):
                self.connection = connection
                
                // Send app to server.
                self.sendApp(at: fileURL, via: connection) { (result) in
                    switch result
                    {
                    case .failure(let error): self.finish(.failure(error))
                    case .success:
                        self.progress.completedUnitCount += 1
                        
                        // Receive response from server.
                        let progress = self.receiveResponse(from: connection) { (result) in
                            switch result
                            {
                            case .failure(let error): self.finish(.failure(error))
                            case .success: self.finish(.success(()))
                            }
                        }
                        
                        self.progress.addChild(progress, withPendingUnitCount: 3)
                    }
                }
            }
        }
    }
    
    override func finish(_ result: Result<Void, Error>)
    {
        super.finish(result)
        
        if let connection = self.connection
        {
            connection.cancel()
        }
    }
}

private extension InstallAppOperation
{
    func connect(completionHandler: @escaping (Result<NWConnection, Error>) -> Void)
    {
        guard let server = ServerManager.shared.discoveredServers.first else { return completionHandler(.failure(InstallationError.serverNotFound)) }
        
        let connection = NWConnection(to: .service(name: server.service.name, type: server.service.type, domain: server.service.domain, interface: nil), using: .tcp)
        
        connection.stateUpdateHandler = { [unowned connection] (state) in
            switch state
            {
            case .failed(let error):
                print("Failed to connect to service \(server.service.name).", error)
                completionHandler(.failure(InstallationError.connectionFailed))
               
            case .cancelled:
                completionHandler(.failure(OperationError.cancelled))
                
            case .ready:
                completionHandler(.success(connection))
            
            case .waiting: break
            case .setup: break
            case .preparing: break
            @unknown default: break
            }
        }
        
        connection.start(queue: self.dispatchQueue)
    }
    
    func sendApp(at fileURL: URL, via connection: NWConnection, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            guard let appData = try? Data(contentsOf: fileURL) else { throw InstallationError.invalidApp }
            guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
            
            let request = ServerRequest(udid: udid, contentSize: appData.count)
            let requestData: Data
                
            do {
                requestData = try JSONEncoder().encode(request)
            }
            catch {
                print("Invalid request.", error)
                throw ALTServerError(.invalidRequest)
            }
            
            let requestSize = Int32(requestData.count)
            let requestSizeData = withUnsafeBytes(of: requestSize) { Data($0) }
            
            func process(_ error: Error?) -> Bool
            {
                if error != nil
                {
                    completionHandler(.failure(InstallationError.connectionDropped))
                    return false
                }
                else
                {
                    return true
                }
            }
            
            // Send request data size.
            print("Sending request data size \(requestSize)")
            connection.send(content: requestSizeData, completion: .contentProcessed { (error) in
                guard process(error) else { return }
                
                // Send request.
                print("Sending request \(request)")
                connection.send(content: requestData, completion: .contentProcessed { (error) in
                    guard process(error) else { return }
                    
                    // Send app data.
                    print("Sending app data (Size: \(appData.count))")
                    connection.send(content: appData, completion: .contentProcessed { (error) in
                        print("Sent app data!")
                        
                        guard process(error) else { return }
                        completionHandler(.success(()))
                    })
                })
            })
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func receiveResponse(from connection: NWConnection, completionHandler: @escaping (Result<Void, Error>) -> Void) -> Progress
    {
        func receive(from connection: NWConnection, progress: Progress, completionHandler: @escaping (Result<Void, Error>) -> Void)
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
                            print(response)
                            
                            if let error = response.error
                            {
                                completionHandler(.failure(error))
                            }
                            else if response.progress == 1.0
                            {
                                completionHandler(.success(()))
                            }
                            else
                            {
                                progress.completedUnitCount = Int64(response.progress * 100)
                                receive(from: connection, progress: progress, completionHandler: completionHandler)
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
        
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        receive(from: connection, progress: progress, completionHandler: completionHandler)
        return progress
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
