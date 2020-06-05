//
//  ConnectionManager.swift
//  AltServer
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltKit

typealias ConnectionManager = AltKit.ConnectionManager<RequestHandler>

private let connectionManager = ConnectionManager(requestHandler: RequestHandler(),
                                                  connectionHandlers: [LocalConnectionHandler()])

extension ConnectionManager
{
    static var shared: ConnectionManager {
        return connectionManager
    }
}

struct RequestHandler: AltKit.RequestHandler
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
                
                try AppManager.shared.installApp(at: fileURL, bundleIdentifier: bundleIdentifier, activeProfiles: request.activeProfiles)

                print("Installed app with result:", result)
                
                let response = InstallationProgressResponse(progress: 1.0)
                completionHandler(.success(response))
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
        do
        {
            try AppManager.shared.install(request.provisioningProfiles, activeProfiles: request.activeProfiles)
            
            print("Installed profiles:", request.provisioningProfiles.map { $0.bundleIdentifier })
            
            let response = InstallProvisioningProfilesResponse()
            completionHandler(.success(response))
        }
        catch
        {
            print("Failed to install profiles \(request.provisioningProfiles.map { $0.bundleIdentifier }):", error)
            completionHandler(.failure(error))
        }
    }
    
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void)
    {
        do
        {
            try AppManager.shared.removeProvisioningProfiles(forBundleIdentifiers: request.bundleIdentifiers)
            
            print("Removed profiles:", request.bundleIdentifiers)
            
            let response = RemoveProvisioningProfilesResponse()
            completionHandler(.success(response))
        }
        catch
        {
            print("Failed to remove profiles \(request.bundleIdentifiers):", error)
            completionHandler(.failure(error))
        }
    }
    
    func handleRemoveAppRequest(_ request: RemoveAppRequest, for connection: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void)
    {
        AppManager.shared.removeApp(forBundleIdentifier: request.bundleIdentifier)
        
        print("Removed app:", request.bundleIdentifier)
        
        let response = RemoveAppResponse()
        completionHandler(.success(response))
    }
}
