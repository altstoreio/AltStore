//
//  DaemonRequestHandler.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

typealias DaemonConnectionManager = ConnectionManager<DaemonRequestHandler>

private let connectionManager = ConnectionManager(requestHandler: DaemonRequestHandler(),
                                                  connectionHandlers: [XPCConnectionHandler()])

extension DaemonConnectionManager
{
    static var shared: ConnectionManager {
        return connectionManager
    }
}

struct DaemonRequestHandler: RequestHandler
{
    func handleAnisetteDataRequest(_ request: AnisetteDataRequest, for connection: Connection, completionHandler: @escaping (Result<AnisetteDataResponse, Error>) -> Void)
    {
        do
        {
            let anisetteData = try AnisetteDataManager.shared.requestAnisetteData()
            
            let response = AnisetteDataResponse(anisetteData: anisetteData)
            completionHandler(.success(response))
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: Connection, completionHandler: @escaping (Result<InstallationProgressResponse, Error>) -> Void)
    {
        guard let fileURL = request.fileURL else { return completionHandler(.failure(ALTServerError(.invalidRequest))) }
        
        print("Awaiting begin installation request...")
        
        connection.receiveRequest() { (result) in
            print("Received begin installation request with result:", result)
            
            do
            {
                guard case .beginInstallation(let request) = try result.get() else { throw ALTServerError(.unknownRequest) }
                guard let bundleIdentifier = request.bundleIdentifier else { throw ALTServerError(.invalidRequest) }
                
                AppManager.shared.installApp(at: fileURL, bundleIdentifier: bundleIdentifier, activeProfiles: request.activeProfiles) { (result) in
                    let result = result.map { InstallationProgressResponse(progress: 1.0) }
                    print("Installed app with result:", result)
                    
                    completionHandler(result)
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for connection: Connection,
                                                  completionHandler: @escaping (Result<InstallProvisioningProfilesResponse, Error>) -> Void)
    {
        AppManager.shared.install(request.provisioningProfiles, activeProfiles: request.activeProfiles) { (result) in
            switch result
            {
            case .failure(let error):
                print("Failed to install profiles \(request.provisioningProfiles.map { $0.bundleIdentifier }):", error)
                completionHandler(.failure(error))
                
            case .success:
                print("Installed profiles:", request.provisioningProfiles.map { $0.bundleIdentifier })
                
                let response = InstallProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }
    
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void)
    {
        AppManager.shared.removeProvisioningProfiles(forBundleIdentifiers: request.bundleIdentifiers) { (result) in
            switch result
            {
            case .failure(let error):
                print("Failed to remove profiles \(request.bundleIdentifiers):", error)
                completionHandler(.failure(error))
                
            case .success:
                print("Removed profiles:", request.bundleIdentifiers)
                
                let response = RemoveProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }
    
    func handleRemoveAppRequest(_ request: RemoveAppRequest, for connection: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void)
    {
        AppManager.shared.removeApp(forBundleIdentifier: request.bundleIdentifier) { (result) in
            switch result
            {
            case .failure(let error):
                print("Failed to remove app \(request.bundleIdentifier):", error)
                completionHandler(.failure(error))
                
            case .success:
                print("Removed app:", request.bundleIdentifier)
                
                let response = RemoveAppResponse()
                completionHandler(.success(response))
            }
        }
    }
}
