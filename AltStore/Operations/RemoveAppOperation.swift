//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

@objc(RemoveAppOperation)
class RemoveAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters())) }
        
        Logger.sideload.notice("Removing app \(self.context.bundleIdentifier, privacy: .public)...")
        
        installedApp.managedObjectContext?.perform {
            let bundleIdentifier = installedApp.resignedBundleIdentifier

            Task<Void, Never>
            {
                do
                {
                    // Prefer on-device when a pairing file is available; fall back to AltServer otherwise.
                    if AppManager.shared.devicePairingFile != nil
                    {
                        try await self.removeOnDevice(bundleIdentifier: bundleIdentifier)
                    }
                    else if let server = self.context.server
                    {
                        guard let udid = UserDefaults.shared.deviceID else { throw OperationError.unknownUDID }

                        try await self.removeViaServer(bundleIdentifier: bundleIdentifier, server: server, udid: udid)
                    }
                    else
                    {
                        throw OperationError.serverNotFound
                    }
                    
                    self.progress.completedUnitCount += 1
                    Logger.sideload.notice("Successfully removed app \(self.context.bundleIdentifier, privacy: .public)!")

                    // The 'await' version of performBackgroundTask drops the context before it can be used.
                    // Sync function is a workaround to match the original pattern.
                    func finishOnBackgroundContext()
                    {
                        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                            let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                            installedApp.isActive = false
                            self.finish(.success(installedApp))
                        }
                    }
                    
                    finishOnBackgroundContext()
                }
                catch
                {
                    Logger.sideload.notice("Failed to remove \(self.context.bundleIdentifier, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    self.finish(.failure(error))
                }
            }
        }
    }
}

private extension RemoveAppOperation
{
    func removeOnDevice(bundleIdentifier: String) async throws
    {
        do
        {
            let client = try AppManager.shared.makeOnDeviceClient()
            try await client.removeApp(bundleIdentifier: bundleIdentifier)
            Logger.sideload.notice("Removed app \(bundleIdentifier, privacy: .public) from device")
        }
        catch
        {
            Logger.sideload.error("Failed to remove app \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw (error as NSError).withLocalizedFailure(String(localized: "Failed to remove app."))
        }
    }

    func removeViaServer(bundleIdentifier: String, server: Server, udid: String) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success(let connection):
                    Logger.sideload.debug("Sending remove app request...")

                    let request = RemoveAppRequest(udid: udid, bundleIdentifier: bundleIdentifier)
                    connection.send(request) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            Logger.sideload.error("Failed to send remove app request. \(error.localizedDescription, privacy: .public)")
                            continuation.resume(throwing: error)

                        case .success:
                            Logger.sideload.debug("Waiting for remove app response...")
                            connection.receiveResponse() { (result) in
                                switch result
                                {
                                case .failure(let error):
                                    Logger.sideload.error("Failed to receive remove app response. \(error.localizedDescription, privacy: .public)")
                                    continuation.resume(throwing: error)

                                case .success(.error(let response)):
                                    Logger.sideload.error("Failed to remove app. \(response.error.localizedDescription, privacy: .public)")
                                    continuation.resume(throwing: response.error)

                                case .success(.removeApp): continuation.resume()

                                case .success: continuation.resume(throwing: ALTServerError(.unknownResponse))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

