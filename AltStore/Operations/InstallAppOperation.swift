//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network

import AltStoreCore
import AltSign
import Roxas

@objc(InstallAppOperation)
class InstallAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    private var didCleanUp = false
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let certificate = self.context.certificate,
            let resignedApp = self.context.resignedApp,
            let connection = self.context.installationConnection
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        Logger.sideload.notice("Installing resigned app \(resignedApp.bundleIdentifier, privacy: .public)...")
        
        @Managed var appVersion = self.context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        backgroundContext.perform {
            
            /* App */
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: resignedApp,
                                            originalBundleIdentifier: self.context.bundleIdentifier,
                                            certificateSerialNumber: certificate.serialNumber,
                                            storeBuildVersion: storeBuildVersion,
                                            context: backgroundContext)
            }
            
            installedApp.update(resignedApp: resignedApp, certificateSerialNumber: certificate.serialNumber, storeBuildVersion: storeBuildVersion)
            installedApp.needsResign = false
            
            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext)
            {
                installedApp.team = team
            }
            
            /* App Extensions */
            var installedExtensions = Set<InstalledExtension>()
            
            if
                let bundle = Bundle(url: resignedApp.fileURL),
                let directory = bundle.builtInPlugInsURL,
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            {
                for case let fileURL as URL in enumerator
                {
                    guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                    guard let appExtension = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }
                    
                    let parentBundleID = self.context.bundleIdentifier
                    let resignedParentBundleID = resignedApp.bundleIdentifier
                    
                    let resignedBundleID = appExtension.bundleIdentifier
                    let originalBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: parentBundleID)
                    
                    let installedExtension: InstalledExtension
                    
                    if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == originalBundleID })
                    {
                        installedExtension = appExtension
                    }
                    else
                    {
                        installedExtension = InstalledExtension(resignedAppExtension: appExtension, originalBundleIdentifier: originalBundleID, context: backgroundContext)
                    }
                    
                    installedExtension.update(resignedAppExtension: appExtension)
                    
                    installedExtensions.insert(installedExtension)
                }
            }
            
            installedApp.appExtensions = installedExtensions
            
            self.context.beginInstallationHandler?(installedApp)
            
            // Temporary directory and resigned .ipa no longer needed, so delete them now to ensure AltStore doesn't quit before we get the chance to.
            self.cleanUp()
            
            var activeProfiles: Set<String>?
            if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit
            {
                // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
                
                let fetchRequest = InstalledApp.activeAppsFetchRequest()
                fetchRequest.includesPendingChanges = false
                
                var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
                if !activeApps.contains(installedApp)
                {
                    let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
                    let availableActiveApps = max(sideloadedAppsLimit - activeAppsCount, 0)
                    if installedApp.requiredActiveSlots <= availableActiveApps
                    {
                        // This app has not been explicitly activated, but there are enough slots available,
                        // so implicitly activate it.
                        installedApp.isActive = true
                        activeApps.append(installedApp)
                    }
                    else
                    {
                        installedApp.isActive = false
                    }
                }

                activeProfiles = Set(activeApps.flatMap { (installedApp) -> [String] in
                    let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                    return [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                })
            }
            
            let resignedBundleID = installedApp.resignedBundleIdentifier
            
            let request = BeginInstallationRequest(activeProfiles: activeProfiles, bundleIdentifier: resignedBundleID)
            connection.send(request) { (result) in
                switch result
                {
                case .failure(let error): 
                    Logger.sideload.notice("Failed to send begin installation request for resigned app \(resignedBundleID, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    self.finish(.failure(error))
                    
                case .success:
                    Logger.sideload.notice("Sent begin installation request for resigned app \(resignedBundleID, privacy: .public).")
                    
                    self.receive(from: connection) { (result) in
                        switch result
                        {
                        case .success:
                            backgroundContext.perform {
                                Logger.sideload.notice("Successfully installed resigned app \(resignedBundleID, privacy: .public)!")
                                
                                installedApp.refreshedDate = Date()
                                self.finish(.success(installedApp))
                            }
                            
                        case .failure(let error):
                            Logger.sideload.notice("Failed to install resigned app \(resignedBundleID, privacy: .public). \(error.localizedDescription, privacy: .public)")
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        }
    }
    
    override func finish(_ result: Result<InstalledApp, Error>)
    {
        self.cleanUp()
        
        // Only remove refreshed IPA when finished.
        if let app = self.context.app
        {
            let fileURL = InstalledApp.refreshedIPAURL(for: app)
            
            do
            {
                try FileManager.default.removeItem(at: fileURL)
            }
            catch
            {
                Logger.sideload.error("Failed to remove refreshed .ipa: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        super.finish(result)
    }
}

private extension InstallAppOperation
{
    func receive(from connection: ServerConnection, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        connection.receiveResponse() { (result) in
            do
            {
                let response = try result.get()
                                
                switch response
                {
                case .installationProgress(let response):
                    Logger.sideload.debug("Installing \(self.context.resignedApp?.bundleIdentifier ?? self.context.bundleIdentifier, privacy: .public)... \((response.progress * 100).rounded())%")
                    
                    if response.progress == 1.0
                    {
                        self.progress.completedUnitCount = self.progress.totalUnitCount
                        completionHandler(.success(()))
                    }
                    else
                    {
                        self.progress.completedUnitCount = Int64(response.progress * 100)
                        self.receive(from: connection, completionHandler: completionHandler)
                    }
                    
                case .error(let response):
                    completionHandler(.failure(response.error))
                    
                default:
                    completionHandler(.failure(ALTServerError(.unknownRequest)))
                }
            }
            catch
            {
                completionHandler(.failure(ALTServerError(error)))
            }
        }
    }
    
    func cleanUp()
    {
        guard !self.didCleanUp else { return }
        self.didCleanUp = true
        
        do
        {
            try FileManager.default.removeItem(at: self.context.temporaryDirectory)
        }
        catch
        {
            Logger.sideload.error("Failed to remove temporary directory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
