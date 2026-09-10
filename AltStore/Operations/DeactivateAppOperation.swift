//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(DeactivateAppOperation)
class DeactivateAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable
{
    let app: InstalledApp
    let context: OperationContext
    
    init(app: InstalledApp, context: OperationContext)
    {
        self.app = app
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
        
        Logger.sideload.notice("Deactivating app \(self.app.bundleIdentifier, privacy: .public)...")
        
        self.app.managedObjectContext?.perform {
            let appExtensionIdentifiers = self.app.appExtensions.map { $0.resignedBundleIdentifier }
            let bundleIdentifiers = Set([self.app.resignedBundleIdentifier] + appExtensionIdentifiers)

            Task<Void, Never>
            {
                do
                {
                    // Deactivate on-device when Remote AltServer is set up and preferred; fall back to AltServer otherwise.
                    if UserDefaults.shared.prefersRemoteAltServer
                    {
                        try await self.deactivateOnDevice(bundleIdentifiers: bundleIdentifiers)
                    }
                    else if let server = self.context.server
                    {
                        guard let udid = UserDefaults.shared.deviceID else { throw OperationError.unknownUDID }

                        try await self.deactivateViaServer(bundleIdentifiers: bundleIdentifiers, server: server, udid: udid)
                    }
                    else
                    {
                        throw OperationError.serverNotFound
                    }
                    
                    self.progress.completedUnitCount += 1
                    Logger.sideload.notice("Successfully deactivated app \(self.app.bundleIdentifier, privacy: .public)!")

                    // The 'await' version of performBackgroundTask drops the context before it can be used.
                    // Sync function is a workaround to match the original pattern.
                    func finishOnBackgroundContext()
                    {
                        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                            let installedApp = context.object(with: self.app.objectID) as! InstalledApp
                            installedApp.isActive = false
                            self.finish(.success(installedApp))
                        }
                    }
                    
                    finishOnBackgroundContext()
                }
                catch
                {
                    Logger.sideload.notice("Failed to deactivate \(self.app.bundleIdentifier, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    self.finish(.failure(error))
                }
            }
        }
    }
}

private extension DeactivateAppOperation
{
    // Mirrors AltServer's `removeProvisioningProfilesForBundleIdentifiers:`: list profiles
    // installed on the device, filter by bundle identifier, remove each by UUID.
    func deactivateOnDevice(bundleIdentifiers: Set<String>) async throws
    {
        // misagent doesn't expose a remove-by-bundle-ID primitive, so list the installed
        // profiles and filter to the ones we want to remove.
        let client = try AppManager.shared.makeOnDeviceClient()
        
        let profiles: [ALTProvisioningProfile]
        do
        {
            profiles = try await client.installedProvisioningProfiles()
        }
        catch
        {
            Logger.sideload.error("Failed to list provisioning profiles: \(error.localizedDescription, privacy: .public)")
            throw (error as NSError).withLocalizedFailure(String(localized: "Failed to deactivate app."))
        }

        for profile in profiles where bundleIdentifiers.contains(profile.bundleIdentifier)
        {
            do
            {
                try await client.removeProvisioningProfile(profile)
                Logger.sideload.notice("Removed provisioning profile for \(profile.bundleIdentifier, privacy: .public)")
            }
            catch
            {
                Logger.sideload.error("Failed to remove provisioning profile for \(profile.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw (error as NSError).withLocalizedFailure(String(localized: "Failed to deactivate app."))
            }
        }
    }

    func deactivateViaServer(bundleIdentifiers: Set<String>, server: Server, udid: String) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success(let connection):
                    Logger.sideload.notice("Sending deactivate app request...")

                    let request = RemoveProvisioningProfilesRequest(udid: udid, bundleIdentifiers: bundleIdentifiers)
                    connection.send(request) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            Logger.sideload.error("Failed to send deactivate app request. \(error.localizedDescription, privacy: .public)")
                            continuation.resume(throwing: error)

                        case .success:
                            Logger.sideload.debug("Waiting for deactivate app response...")
                            connection.receiveResponse() { (result) in
                                switch result
                                {
                                case .failure(let error):
                                    Logger.sideload.error("Failed to receive deactivate app response. \(error.localizedDescription, privacy: .public)")
                                    continuation.resume(throwing: error)

                                case .success(.error(let response)):
                                    Logger.sideload.error("Failed to deactivate app. \(response.error.localizedDescription, privacy: .public)")
                                    continuation.resume(throwing: response.error)

                                case .success(.removeProvisioningProfiles): continuation.resume()

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
