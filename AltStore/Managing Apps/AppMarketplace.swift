//
//  AppMarketplace.swift
//  AltStore
//
//  Created by Riley Testut on 1/26/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import MarketplaceKit
import CoreData

import AltStoreCore

// App == InstalledApp

@available(iOS 17.4, *)
extension AppLibrary
{
    //TODO: Tie to iCloud value
    static let `defaultAccount` = "AltStore"
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    struct InstallTaskContext
    {
        @TaskLocal
        static var bundleIdentifier: String = ""
        
        @TaskLocal
        static var beginInstallationHandler: ((String) -> Void)?
        
        @TaskLocal
        static var operationContext: OperationContext = OperationContext()
        
        @TaskLocal
        static var progress: Progress = Progress.discreteProgress(totalUnitCount: 100)
        
        @TaskLocal
        static var presentingViewController: UIViewController?
    }
    
    struct InstallVerificationTokenRequest: Encodable
    {
        var bundleID: String
    }

    struct InstallVerificationTokenResponse: Decodable
    {
        var token: String
    }
}

@available(iOS 17.4, *)
actor AppMarketplace
{
    static let shared = AppMarketplace()
    
    private init()
    {
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func update() async
    {
        do
        {
            let installedMarketplaceIDs = await Set(AppLibrary.current.installedApps.map(\.id))
            
            //TODO: Uncomment when we can actually test this
//            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
//            try await context.performAsync {
//                
//                let installedApps = InstalledApp.all(in: context)
//                for installedApp in installedApps
//                {
//                    // Ignore any installed apps without valid marketplace StoreApp.
//                    guard let storeApp = installedApp.storeApp, let marketplaceID = storeApp.marketplaceID else { continue }
//                    
//                    // Ignore any apps we are actively installing.
//                    guard !AppManager.shared.isActivelyManagingApp(withBundleID: installedApp.bundleIdentifier) else { continue }
//                    
//                    if !installedMarketplaceIDs.contains(marketplaceID)
//                    {
//                        // This app is no longer installed, so delete.
//                        context.delete(installedApp)
//                    }
//                }
//                
//                try context.save()
//            }
        }
        catch
        {
            Logger.main.error("Failed to update installed apps. \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func install(@AsyncManaged _ storeApp: StoreApp, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let progress = InstallTaskContext.progress
        
        let operation = AppManager.AppOperation.install(storeApp)
        AppManager.shared.set(progress, for: operation)
        
        let bundleID = await $storeApp.bundleIdentifier
        
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.$bundleIdentifier.withValue(bundleID) {
                try await InstallTaskContext.$beginInstallationHandler.withValue(beginInstallationHandler) {
                    do
                    {
                        let installedApp = try await self.install(storeApp, presentingViewController: presentingViewController, operation: operation)
                        await installedApp.perform {
                            self.finish(operation, result: .success($0), progress: progress)
                        }
                        
                        return installedApp
                    }
                    catch
                    {
                        self.finish(operation, result: .failure(error), progress: progress)
                        
                        throw error
                    }
                }
            }
        }
        
        return (task, progress)
    }
    
    func update(@AsyncManaged _ installedApp: InstalledApp, to version: AltStoreCore.AppVersion? = nil, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let (appName, bundleID) = await $installedApp.perform { ($0.name, $0.bundleIdentifier) }
        
        let latestSupportedVersion = await $installedApp.perform({ $0.storeApp?.latestSupportedVersion })
        guard let appVersion = version ?? latestSupportedVersion else {
            let task = Task<AsyncManaged<InstalledApp>, Error> { throw OperationError.appNotFound(name: appName) }
            return (task, Progress.discreteProgress(totalUnitCount: 1))
        }
        
        let progress = InstallTaskContext.progress
        
        let operation = AppManager.AppOperation.update(installedApp)
        AppManager.shared.set(progress, for: operation)
        
        let installationHandler = { (bundleID: String) in
            if bundleID == StoreApp.altstoreAppID
            {
                // AltStore will quit before installation finishes,
                // so assume if we get this far the update will finish successfully.
                let event = AnalyticsManager.Event.updatedApp(installedApp)
                AnalyticsManager.shared.trackEvent(event)
            }
            
            beginInstallationHandler?(bundleID)
        }
                
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.$bundleIdentifier.withValue(bundleID) {
                try await InstallTaskContext.$beginInstallationHandler.withValue(installationHandler) {
                    do
                    {
                        let installedApp = try await self.update(appVersion, presentingViewController: presentingViewController, operation: operation)
                        await installedApp.perform {
                            self.finish(operation, result: .success($0), progress: progress)
                        }
                        
                        return installedApp
                    }
                    catch
                    {
                        self.finish(operation, result: .failure(error), progress: progress)
                        
                        throw error
                    }
                }
            }
        }
        
        return (task, progress)
    }
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    func install(@AsyncManaged _ storeApp: StoreApp, presentingViewController: UIViewController?, operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        // Verify pledge
        try await self.verifyPledge(for: storeApp, presentingViewController: presentingViewController)
        
        // Verify version is supported
        guard let latestAppVersion = await $storeApp.latestAvailableVersion else {
            let failureReason = await String(format: NSLocalizedString("The latest version of %@ could not be determined.", comment: ""), $storeApp.name)
            throw OperationError.unknown(failureReason: failureReason) //TODO: Make proper error case
        }
        
        var appVersion = latestAppVersion
        
        do
        {
            // Verify app version is supported
            try await $storeApp.perform { _ in
                try self.verify(latestAppVersion)
            }
        }
        catch let error as VerificationError where error.code == .iOSVersionNotSupported
        {
            guard let presentingViewController, let latestSupportedVersion = await $storeApp.latestSupportedVersion else { throw error }
            
            if let installedApp = await $storeApp.installedApp
            {
                guard !installedApp.matches(latestSupportedVersion) else { throw error }
            }
            
            let title = NSLocalizedString("Unsupported iOS Version", comment: "")
            let message = error.localizedDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
            let localizedVersion = latestSupportedVersion.localizedVersion
            
            let action = await UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), $storeApp.name, localizedVersion), style: .default)
            try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
            
            appVersion = latestSupportedVersion
        }
        
        // Install app
        let installedApp = try await self._install(appVersion, operation: operation)
        return installedApp
    }
    
    func update(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, presentingViewController: UIViewController?, operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        guard let storeApp = await $appVersion.storeApp else { throw await OperationError.appNotFound(name: $appVersion.name) }
        
        // Verify pledge
        try await self.verifyPledge(for: storeApp, presentingViewController: presentingViewController)
        
        // Install app
        let installedApp = try await self._install(appVersion, operation: operation)
        return installedApp
    }
}

// Operations
@available(iOS 17.4, *)
private extension AppMarketplace
{
    func verifyPledge(for storeApp: StoreApp, presentingViewController: UIViewController?) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let verifyPledgeOperation = VerifyAppPledgeOperation(storeApp: storeApp, presentingViewController: presentingViewController)
            verifyPledgeOperation.resultHandler = { result in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success: continuation.resume()
                }
            }
            
            AppManager.shared.run([verifyPledgeOperation], context: InstallTaskContext.operationContext)
        }
    }
    
    func verify(_ appVersion: AltStoreCore.AppVersion) throws
    {
        if let minOSVersion = appVersion.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            throw VerificationError.iOSVersionNotSupported(app: appVersion, requiredOSVersion: minOSVersion)
        }
        else if let maxOSVersion = appVersion.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            throw VerificationError.iOSVersionNotSupported(app: appVersion, requiredOSVersion: maxOSVersion)
        }
    }
    
    func _install(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        @AsyncManaged
        var storeApp: StoreApp
        
        guard let _app = await $appVersion.app else {
            //TODO: Make this a proper error
            let failureReason = NSLocalizedString("The app listing could not be found.", comment: "")
            throw OperationError.unknown(failureReason: failureReason)
        }
        storeApp = _app
        
        //TODO: Latest available, or latest supported?
        guard let marketplaceID = await $storeApp.marketplaceID else {
            //TODO: Make this a proper error
            let failureReason = await String(format: NSLocalizedString("The marketplace ID for %@ could not be determined.", comment: ""), $storeApp.name)
            throw OperationError.unknown(failureReason: failureReason)
        }
        
        let bundleID = await $storeApp.bundleIdentifier
        InstallTaskContext.beginInstallationHandler?(bundleID) // TODO: Is this called too early?
        
        let installVerificationToken = try await self.requestInstallToken(bundleID: bundleID)
        let packageURL = await $appVersion.downloadURL
        
        // Save app info to keychain so MarketplaceExtension can read it.
        try Keychain.shared.setPendingInstall(for: appVersion, installVerificationToken: installVerificationToken)
        
        defer {
            //TODO: Verify assumption this scope doesn't exit until after app finishes installing.
            do
            {
                // Remove pending installation info from Keychain.
                try Keychain.shared.removePendingInstall(for: marketplaceID)
            }
            catch
            {
                Logger.main.error("Failed to remove pending installation for app \(bundleID). \(error.localizedDescription, privacy: .public)")
            }
        }
        
        let task: Task<Void, Error>
        switch operation
        {
        case .update: task = Task { try await AppLibrary.current.requestAppUpdate(for: packageURL, account: AppLibrary.defaultAccount, installVerificationToken: installVerificationToken) }
        default: task = Task { try await AppLibrary.current.requestAppInstallation(for: packageURL, account: AppLibrary.defaultAccount, installVerificationToken: installVerificationToken) }
        }
        
        let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
        
        if let installation = await localApp.installation
        {
            InstallTaskContext.progress.addChild(installation.progress, withPendingUnitCount: InstallTaskContext.progress.totalUnitCount)
        }
        
        try await task.value
        
        guard let installedMetadata = await localApp.installedMetadata else {
            let failureReason = await String(format: NSLocalizedString("The installed metadata for %@ could not be determined.", comment: ""), $storeApp.name)
            throw OperationError.unknown(failureReason: failureReason) //TODO: Make proper error case
        }
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        let installedApp = await backgroundContext.performAsync {
            
            let storeApp = backgroundContext.object(with: storeApp.objectID) as! StoreApp
            let appVersion = backgroundContext.object(with: appVersion.objectID) as! AltStoreCore.AppVersion
            
            /* App */
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(marketplaceApp: storeApp, context: backgroundContext)
            }
            
            installedApp.update(for: installedMetadata, appVersion: appVersion)
            
            //TODO: Include app extensions?
            
            return installedApp
        }
        
        return AsyncManaged(wrappedValue: installedApp)
    }
    
    func requestInstallToken(bundleID: String) async throws -> String
    {
        let requestURL = URL(string: "http://192.168.1.207:7071/api/token")!
        
        let payload = InstallVerificationTokenRequest(bundleID: bundleID)
        let bodyData = try JSONEncoder().encode(payload)
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse
        {
            guard httpResponse.statusCode == 200 else { throw OperationError.unknown() } //TODO: Proper error
        }
        
        let responseJSON = try Foundation.JSONDecoder().decode(InstallVerificationTokenResponse.self, from: data)
        return responseJSON.token
    }
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    func finish(_ operation: AppManager.AppOperation, result: Result<InstalledApp, Error>, progress: Progress?)
    {
        // Must remove before saving installedApp.
        if let currentProgress = AppManager.shared.progress(for: operation), currentProgress == progress
        {
            // Only remove progress if it hasn't been replaced by another one.
            AppManager.shared.set(nil, for: operation)
        }
        
        do
        {
            let installedApp = try result.get()
            
            if installedApp.bundleIdentifier == StoreApp.altstoreAppID
            {
                AppManager.shared.scheduleExpirationWarningLocalNotification(for: installedApp)
            }
            
            let event: AnalyticsManager.Event?
            
            switch operation
            {
            case .install: event = .installedApp(installedApp)
            case .refresh: event = .refreshedApp(installedApp)
            case .update where installedApp.bundleIdentifier == StoreApp.altstoreAppID:
                // AltStore quits before update finishes, so we've preemptively logged this update event.
                // In case AltStore doesn't quit, such as when update has a different bundle identifier,
                // make sure we don't log this update event a second time.
                event = nil
                
            case .update: event = .updatedApp(installedApp)
            case .activate, .deactivate, .backup, .restore: event = nil
            }
            
            if let event = event
            {
                AnalyticsManager.shared.trackEvent(event)
            }
            
            // No widget included in Marketplace version of AltStore.
            // WidgetCenter.shared.reloadAllTimelines()
            
            try installedApp.managedObjectContext?.save()
        }
        catch let nsError as NSError
        {
            var appName: String!
            if let app = operation.app as? (NSManagedObject & AppProtocol)
            {
                if let context = app.managedObjectContext
                {
                    context.performAndWait {
                        appName = app.name
                    }
                }
                else
                {
                    appName = NSLocalizedString("App", comment: "")
                }
            }
            else
            {
                appName = operation.app.name
            }
            
            let localizedTitle: String
            switch operation
            {
            case .install: localizedTitle = String(format: NSLocalizedString("Failed to Install %@", comment: ""), appName)
            case .refresh: localizedTitle = String(format: NSLocalizedString("Failed to Refresh %@", comment: ""), appName)
            case .update: localizedTitle = String(format: NSLocalizedString("Failed to Update %@", comment: ""), appName)
            case .activate: localizedTitle = String(format: NSLocalizedString("Failed to Activate %@", comment: ""), appName)
            case .deactivate: localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@", comment: ""), appName)
            case .backup: localizedTitle = String(format: NSLocalizedString("Failed to Back Up %@", comment: ""), appName)
            case .restore: localizedTitle = String(format: NSLocalizedString("Failed to Restore %@ Backup", comment: ""), appName)
            }
            
            let error = nsError.withLocalizedTitle(localizedTitle)
            AppManager.shared.log(error, operation: operation.loggedErrorOperation, app: operation.app)
        }
    }
}
