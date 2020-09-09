//
//  ConnectionManager.swift
//  AltServer
//
//  Created by Riley Testut on 5/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

public protocol RequestHandler
{
    func handleAnisetteDataRequest(_ request: AnisetteDataRequest, for connection: Connection, completionHandler: @escaping (Result<AnisetteDataResponse, Error>) -> Void)
    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: Connection, completionHandler: @escaping (Result<InstallationProgressResponse, Error>) -> Void)
    
    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for connection: Connection,
                                                  completionHandler: @escaping (Result<InstallProvisioningProfilesResponse, Error>) -> Void)
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void)
    
    func handleRemoveAppRequest(_ request: RemoveAppRequest, for connection: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void)
}

public protocol ConnectionHandler: AnyObject
{
    var connectionHandler: ((Connection) -> Void)? { get set }
    var disconnectionHandler: ((Connection) -> Void)? { get set }
    
    func startListening()
    func stopListening()
}

public class ConnectionManager<RequestHandlerType: RequestHandler>
{
    public let requestHandler: RequestHandlerType
    public let connectionHandlers: [ConnectionHandler]
    
    public var isStarted = false
    
    private var connections = [Connection]()
    
    public init(requestHandler: RequestHandlerType, connectionHandlers: [ConnectionHandler])
    {
        self.requestHandler = requestHandler
        self.connectionHandlers = connectionHandlers
        
        for handler in connectionHandlers
        {
            handler.connectionHandler = { [weak self] (connection) in
                self?.prepare(connection)
            }
            
            handler.disconnectionHandler = { [weak self] (connection) in
                self?.disconnect(connection)
            }
        }
    }
    
    public func start()
    {
        guard !self.isStarted else { return }
        
        for connectionHandler in self.connectionHandlers
        {
            connectionHandler.startListening()
        }
        
        self.isStarted = true
    }
    
    public func stop()
    {
        guard self.isStarted else { return }
        
        for connectionHandler in self.connectionHandlers
        {
            connectionHandler.stopListening()
        }
        
        self.isStarted = false
    }
}

private extension ConnectionManager
{
    func prepare(_ connection: Connection)
    {
        guard !self.connections.contains(where: { $0 === connection }) else { return }
        self.connections.append(connection)
        
        self.handleRequest(for: connection)
    }
    
    func disconnect(_ connection: Connection)
    {
        guard let index = self.connections.firstIndex(where: { $0 === connection }) else { return }
        self.connections.remove(at: index)
    }
    
    func handleRequest(for connection: Connection)
    {
        func finish<T: ServerMessageProtocol>(_ result: Result<T, Error>)
        {
            do
            {
                let response = try result.get()
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent response \(response) with result:", result)
                }
            }
            catch
            {
                let response = ErrorResponse(error: ALTServerError(error))
                connection.send(response, shouldDisconnect: true) { (result) in
                    print("Sent error response \(response) with result:", result)
                }
            }
        }
        
        connection.receiveRequest() { (result) in
            print("Received request with result:", result)
            
            switch result
            {
            case .failure(let error): finish(Result<ErrorResponse, Error>.failure(error))
                
            case .success(.anisetteData(let request)):
                self.requestHandler.handleAnisetteDataRequest(request, for: connection) { (result) in
                    finish(result)
                }
                
            case .success(.prepareApp(let request)):
                self.requestHandler.handlePrepareAppRequest(request, for: connection) { (result) in
                    finish(result)
                }
                
            case .success(.beginInstallation): break
                
            case .success(.installProvisioningProfiles(let request)):
                self.requestHandler.handleInstallProvisioningProfilesRequest(request, for: connection) { (result) in
                    finish(result)
                }
                
            case .success(.removeProvisioningProfiles(let request)):
                self.requestHandler.handleRemoveProvisioningProfilesRequest(request, for: connection) { (result) in
                    finish(result)
                }
                
            case .success(.removeApp(let request)):
                self.requestHandler.handleRemoveAppRequest(request, for: connection) { (result) in
                    finish(result)
                }
                
            case .success(.unknown):
                finish(Result<ErrorResponse, Error>.failure(ALTServerError(.unknownRequest)))
            }
        }
    }
}
