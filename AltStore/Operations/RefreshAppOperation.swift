//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

import Minimuxer

@objc(RefreshAppOperation)
class RefreshAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable
{
    let context: AppOperationContext
    
    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        self.managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
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

        guard let profiles = self.context.provisioningProfiles else { return self.finish(.failure(OperationError.invalidParameters())) }
        guard let app = self.context.app else { return self.finish(.failure(OperationError.appNotFound(name: nil))) }

        Logger.sideload.notice("Refreshing provisioning profiles for app \(self.context.bundleIdentifier, privacy: .public)...")

        Task<Void, Never>
        {
            do
            {
                // Prefer minimuxer when a pairing file is available; fall back to AltServer otherwise.
                if AppManager.shared.devicePairingFile != nil
                {
                    try await self.refreshOnDevice(profiles: Set(profiles.values))
                }
                else if let server = self.context.server
                {
                    guard let udid = UserDefaults.shared.deviceID else { throw OperationError.unknownUDID }

                    try await self.refreshViaServer(profiles: profiles, app: app, server: server, udid: udid)
                }
                else
                {
                    throw OperationError.serverNotFound
                }

                self.finishRefresh(profiles: profiles, for: app)
            }
            catch
            {
                Logger.sideload.notice("Failed to refresh \(self.context.bundleIdentifier, privacy: .public). \(error.localizedDescription, privacy: .public)")
                self.finish(.failure(error))
            }
        }
    }
}

private extension RefreshAppOperation
{
    func refreshOnDevice(profiles: Set<ALTProvisioningProfile>) async throws
    {
        guard await AppManager.shared.isReachableOnDevice() else { throw OperationError.vpnNotConnected() }

        for profile in profiles
        {
            do
            {
                try Minimuxer.installProvisioningProfile(profile: profile.data)
            }
            catch
            {
                Logger.sideload.error("Failed to install profile for \(profile.bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw (error as NSError).withLocalizedFailure(String(localized: "Failed to refresh app."))
            }
        }
    }

    func refreshViaServer(profiles: [String: ALTProvisioningProfile], app: ALTApplication, server: Server, udid: String) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success(let connection):
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                        Logger.sideload.debug("Sending refresh app request...")

                        var activeProfiles: Set<String>?
                        if UserDefaults.standard.activeAppsLimit != nil
                        {
                            // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
                            let activeApps = InstalledApp.fetchActiveApps(in: context)
                            activeProfiles = Set(activeApps.flatMap { (installedApp) -> [String] in
                                let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                                return [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                            })
                        }

                        let request = InstallProvisioningProfilesRequest(udid: udid, provisioningProfiles: Set(profiles.values), activeProfiles: activeProfiles)
                        connection.send(request) { (result) in
                            Logger.sideload.debug("Sent refresh app request!")

                            switch result
                            {
                            case .failure(let error): continuation.resume(throwing: error)
                            case .success:
                                Logger.sideload.debug("Waiting for refresh app response...")

                                connection.receiveResponse() { (result) in
                                    switch result
                                    {
                                    case .failure(let error):
                                        Logger.sideload.error("Failed to receive refresh app response. \(error.localizedDescription, privacy: .public)")
                                        continuation.resume(throwing: error)

                                    case .success(.error(let response)):
                                        Logger.sideload.error("Failed to refresh app \(self.context.bundleIdentifier, privacy: .public). \(response.error.localizedDescription, privacy: .public)")
                                        continuation.resume(throwing: response.error)

                                    case .success(.installProvisioningProfiles): continuation.resume()

                                    case .success:
                                        Logger.sideload.notice("Received unknown refresh app response for app \(self.context.bundleIdentifier, privacy: .public)")
                                        continuation.resume(throwing: ALTServerError(.unknownResponse))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Looks up the installed app by bundle id, applies the freshly-installed profiles, then finishes the operation. Shared by both branches.
    func finishRefresh(profiles: [String: ALTProvisioningProfile], for app: ALTApplication)
    {
        self.managedObjectContext.perform {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
            guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                return self.finish(.failure(OperationError.appNotFound(name: app.name)))
            }

            self.progress.completedUnitCount += 1
            Logger.sideload.notice("Refreshed provisioning profiles for app \(self.context.bundleIdentifier, privacy: .public)")

            if let provisioningProfile = profiles[app.bundleIdentifier]
            {
                installedApp.update(provisioningProfile: provisioningProfile)
            }

            for installedExtension in installedApp.appExtensions
            {
                guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
                installedExtension.update(provisioningProfile: provisioningProfile)
            }

            self.finish(.success(installedApp))
        }
    }
}
