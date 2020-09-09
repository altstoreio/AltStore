//
//  RequestHandler.swift
//  AltServer
//
//  Created by Riley Testut on 5/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

typealias ServerConnectionManager = ConnectionManager<ServerRequestHandler>

private let connectionManager = ConnectionManager(requestHandler: ServerRequestHandler(),
                                                  connectionHandlers: [WirelessConnectionHandler(), WiredConnectionHandler()])

extension ServerConnectionManager
{
    static var shared: ConnectionManager {
        return connectionManager
    }
}

struct ServerRequestHandler: RequestHandler
{
    func handleAnisetteDataRequest(_ request: AnisetteDataRequest, for connection: Connection, completionHandler: @escaping (Result<AnisetteDataResponse, Error>) -> Void)
    {
        AnisetteDataManager.shared.requestAnisetteData { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let anisetteData):
                let response = AnisetteDataResponse(anisetteData: anisetteData)
                completionHandler(.success(response))
            }
        }
    }
    
    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: Connection, completionHandler: @escaping (Result<InstallationProgressResponse, Error>) -> Void)
    {
        var temporaryURL: URL?
        
        func finish(_ result: Result<InstallationProgressResponse, Error>)
        {
            if let temporaryURL = temporaryURL
            {
                do { try FileManager.default.removeItem(at: temporaryURL) }
                catch { print("Failed to remove .ipa.", error) }
            }
            
            completionHandler(result)
        }
        
        self.receiveApp(for: request, from: connection) { (result) in
            print("Received app with result:", result)
            
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success(let fileURL):
                temporaryURL = fileURL
                
                print("Awaiting begin installation request...")
                
                connection.receiveRequest() { (result) in
                    print("Received begin installation request with result:", result)
                    
                    switch result
                    {
                    case .failure(let error): finish(.failure(error))
                    case .success(.beginInstallation(let installRequest)):
                        print("Installing app to device \(request.udid)...")
                        
                        self.installApp(at: fileURL, toDeviceWithUDID: request.udid, activeProvisioningProfiles: installRequest.activeProfiles, connection: connection) { (result) in
                            print("Installed app to device with result:", result)
                            switch result
                            {
                            case .failure(let error): finish(.failure(error))
                            case .success:
                                let response = InstallationProgressResponse(progress: 1.0)
                                finish(.success(response))
                            }
                        }
                        
                    case .success: finish(.failure(ALTServerError(.unknownRequest)))
                    }
                }
            }
        }
    }
    
    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for connection: Connection,
                                                  completionHandler: @escaping (Result<InstallProvisioningProfilesResponse, Error>) -> Void)
    {
        ALTDeviceManager.shared.installProvisioningProfiles(request.provisioningProfiles, toDeviceWithUDID: request.udid, activeProvisioningProfiles: request.activeProfiles) { (success, error) in
            if let error = error, !success
            {
                print("Failed to install profiles \(request.provisioningProfiles.map { $0.bundleIdentifier }):", error)
                completionHandler(.failure(ALTServerError(error)))
            }
            else
            {
                print("Installed profiles:", request.provisioningProfiles.map { $0.bundleIdentifier })
                
                let response = InstallProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }
    
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void)
    {
        ALTDeviceManager.shared.removeProvisioningProfiles(forBundleIdentifiers: request.bundleIdentifiers, fromDeviceWithUDID: request.udid) { (success, error) in
            if let error = error, !success
            {
                print("Failed to remove profiles \(request.bundleIdentifiers):", error)
                completionHandler(.failure(ALTServerError(error)))
            }
            else
            {
                print("Removed profiles:", request.bundleIdentifiers)
                
                let response = RemoveProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }
    
    func handleRemoveAppRequest(_ request: RemoveAppRequest, for connection: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void)
    {
        ALTDeviceManager.shared.removeApp(forBundleIdentifier: request.bundleIdentifier, fromDeviceWithUDID: request.udid) { (success, error) in
            if let error = error, !success
            {
                print("Failed to remove app \(request.bundleIdentifier):", error)
                completionHandler(.failure(ALTServerError(error)))
            }
            else
            {
                print("Removed app:", request.bundleIdentifier)
                
                let response = RemoveAppResponse()
                completionHandler(.success(response))
            }
        }
    }
}

private extension RequestHandler
{
    func receiveApp(for request: PrepareAppRequest, from connection: Connection, completionHandler: @escaping (Result<URL, ALTServerError>) -> Void)
    {
        connection.receiveData(expectedSize: request.contentSize) { (result) in
            do
            {
                print("Received app data!")
                
                let data = try result.get()
                                
                guard ALTDeviceManager.shared.availableDevices.contains(where: { $0.identifier == request.udid }) else { throw ALTServerError(.deviceNotFound) }
                
                print("Writing app data...")
                
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                try data.write(to: temporaryURL, options: .atomic)
                
                print("Wrote app to URL:", temporaryURL)
                
                completionHandler(.success(temporaryURL))
            }
            catch
            {
                print("Error processing app data:", error)
                
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }

    func installApp(at fileURL: URL, toDeviceWithUDID udid: String, activeProvisioningProfiles: Set<String>?, connection: Connection, completionHandler: @escaping (Result<Void, ALTServerError>) -> Void)
    {
        let serialQueue = DispatchQueue(label: "com.altstore.ConnectionManager.installQueue", qos: .default)
        var isSending = false
        
        var observation: NSKeyValueObservation?
        
        let progress = ALTDeviceManager.shared.installApp(at: fileURL, toDeviceWithUDID: udid, activeProvisioningProfiles: activeProvisioningProfiles) { (success, error) in
            print("Installed app with result:", error == nil ? "Success" : error!.localizedDescription)
            
            if let error = error.map({ ALTServerError($0) })
            {
                completionHandler(.failure(error))
            }
            else
            {
                completionHandler(.success(()))
            }
            
            observation?.invalidate()
            observation = nil
        }
        
        observation = progress.observe(\.fractionCompleted, changeHandler: { (progress, change) in
            serialQueue.async {
                guard !isSending else { return }
                isSending = true
                
                print("Progress:", progress.fractionCompleted)
                let response = InstallationProgressResponse(progress: progress.fractionCompleted)
                
                connection.send(response) { (result) in
                    serialQueue.async {
                        isSending = false
                    }
                }
            }
        })
    }
}
