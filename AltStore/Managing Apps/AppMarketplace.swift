//
//  AppMarketplace.swift
//  AltStore
//
//  Created by Riley Testut on 1/26/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import MarketplaceKit
import CoreData
import Security

import AltStoreCore

// App == InstalledApp

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
        
        @TaskLocal // Default value is only created once, not per-task, so this is just a dummy Progress.
        static var progress: Progress = Progress.discreteProgress(totalUnitCount: 0)
        
        @MainActor
        static var presentingViewController: UIViewController? {
            return operationContext.presentingViewController
        }
        
        static func withValues<T>(bundleID: String, progress: Progress, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?,
                               operation: () async throws -> T) async rethrows -> T
        {
            let context = OperationContext()
            context.presentingViewController = presentingViewController
            
            return try await InstallTaskContext.$bundleIdentifier.withValue(bundleID) {
                try await InstallTaskContext.$beginInstallationHandler.withValue(beginInstallationHandler) {
                    try await InstallTaskContext.$operationContext.withValue(context) {
                        try await InstallTaskContext.$progress.withValue(progress) {
                            try await operation()
                        }
                    }
                }
            }
        }
    }
    
    struct InstallVerificationTokenRequest: Encodable
    {
        var bundleID: String
        var redownload: Bool
    }

    struct InstallVerificationTokenResponse: Decodable
    {
        var token: String
    }
    
    struct ADPManifest: Decodable
    {
        var appleItemId: String // marketplaceID
        var bundleId: String
        var shortVersionString: String
        var bundleVersion: String
    }
    
    struct PALPromoRequest: Encodable
    {
        var session: String
        var email: String
    }
    
    struct PALPromoResponse: Decodable
    {
        var promoExpiration: Date
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    static let defaultAccount = "AltStore"
    
    #if STAGING
    private static let marketplaceDomain = "https://dev.altstore.io"
    #else
    private static let marketplaceDomain = "https://api.altstore.io"
    #endif
    
    static let requestBaseURL = URL(string: marketplaceDomain)!
}

@available(iOS 17.4, *)
actor AppMarketplace: NSObject
{
    static let shared = AppMarketplace()
    
    private let session = URLSession(configuration: .sharedCookies)
    private let pinnedCertificates: [SecCertificate]
    
    private var didUpdateInstalledApps = false
    
    private override init()
    {
        do
        {
            let certificateURL = Bundle.main.url(forResource: "AltMarketplace", withExtension: "cer")!
            let certificateData = try Data(contentsOf: certificateURL)
                        
            guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: certificateURL]) }
            self.pinnedCertificates = [certificate]
        }
        catch
        {
            Logger.main.error("Failed to configure pinned certificates. \(error.localizedDescription, privacy: .public)")
            self.pinnedCertificates = []
        }
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func update() async
    {
        if !self.didUpdateInstalledApps
        {
            await withCheckedContinuation { continuation in
                Task<Void, Never> { @MainActor in
                    guard AppLibrary.current.isLoading else {
                        return continuation.resume()
                    }
                    
                    _ = withObservationTracking {
                        AppLibrary.current.isLoading
                    } onChange: {
                        Task {
                            continuation.resume()
                        }
                    }
                }
            }
            
            self.didUpdateInstalledApps = true
        }
        
        guard UserDefaults.shared.shouldManageInstalledApps else { return }
        
        let installedMarketplaceApps = await AppLibrary.current.installedApps
        let installedMarketplaceAppsAndMetadata = await MainActor.run { installedMarketplaceApps.map { ($0, $0.installedMetadata) } }
        
        let installedMarketplaceIDs = Set(installedMarketplaceApps.map(\.id))
        Logger.main.debug("Installed Apps: \(installedMarketplaceIDs)")
        
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            try await context.performAsync {
                
                let installedApps = InstalledApp.all(in: context)
                let installedAppsByMarketplaceID = installedApps.filter { $0.storeApp?.marketplaceID != nil }
                    .reduce(into: [UInt64: InstalledApp]()) {
                        $0[$1.storeApp!.marketplaceID!] = $1
                    }
                
                // Remove uninstalled apps
                for installedApp in installedApps where installedApp.bundleIdentifier != StoreApp.altstoreAppID
                {
                    // Ignore any installed apps without valid marketplace StoreApp.
                    guard let storeApp = installedApp.storeApp, let marketplaceID = storeApp.marketplaceID else { continue }

                    // Ignore any apps we are actively installing.
                    guard !AppManager.shared.isActivelyManagingApp(withBundleID: installedApp.bundleIdentifier) else { continue }

                    if !installedMarketplaceIDs.contains(marketplaceID)
                    {
                        // This app is no longer installed, so delete.
                        Logger.main.info("Removing uninstalled app \(installedApp.bundleIdentifier)")
                        context.delete(installedApp)
                    }
                }
                
                // Add missing installed apps (e.g. ones that finished installing after AltStore quit).
                for (marketplaceApp, installedMetadata) in installedMarketplaceAppsAndMetadata where marketplaceApp.id != StoreApp.altstoreMarketplaceID
                {
                    // Check all installed marketplace apps to make sure they are the correct version, not just "new" apps.
                    // guard !installedAppsByMarketplaceID.keys.contains(marketplaceApp.id) else { continue }
                    
                    // Ignore any marketplaceIDs that don't map to a StoreApp.
                    //TODO: Should we make these placeholders?
                    let predicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp._marketplaceID), String(marketplaceApp.id))
                    guard let storeApp = StoreApp.first(satisfying: predicate, in: context) else { continue }
                    
                    let appVersion: AltStoreCore.AppVersion?
                    
                    if let installedMetadata
                    {
                        let version = storeApp.versions.first { $0.version == installedMetadata.shortVersion && $0.buildVersion == installedMetadata.version }
                        
                        // Fall back to latest supported version if no exact match.
                        appVersion = version ?? storeApp.latestSupportedVersion
                    }
                    else
                    {
                        // Fall back to latest supported version if no exact match.
                        appVersion = storeApp.latestSupportedVersion
                    }
                    
                    if let appVersion
                    {
                        if let installedApp = installedAppsByMarketplaceID[marketplaceApp.id], installedApp.matches(appVersion)
                        {
                            // App already exists with this version, so ignore.
                        }
                        else
                        {
                            let installedApp = self.makeInstalledApp(for: storeApp, appVersion: appVersion, in: context)
                            Logger.main.info("Adding/updating installed app \(installedApp.bundleIdentifier) version \(appVersion.localizedVersion)")
                        }
                    }
                }

                try context.save()
            }
        }
        catch
        {
            Logger.main.error("Failed to update installed apps. \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func install(@AsyncManaged _ storeApp: StoreApp, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let operation = AppManager.AppOperation.install(storeApp)
        AppManager.shared.set(progress, for: operation)
        
        let bundleID = await $storeApp.bundleIdentifier
        
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.withValues(bundleID: bundleID, progress: progress, presentingViewController: presentingViewController, beginInstallationHandler: beginInstallationHandler) {
                do
                {
                    let installedApp = try await self.install(storeApp, preferredVersion: nil, presentingViewController: presentingViewController, operation: operation)
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
        
        return (task, progress)
    }
    
    func update(@AsyncManaged _ installedApp: InstalledApp, to version: AltStoreCore.AppVersion? = nil, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let (appName, bundleID) = await $installedApp.perform { ($0.name, $0.bundleIdentifier) }
        
        let (storeApp, latestSupportedVersion) = await $installedApp.perform({ ($0.storeApp, $0.storeApp?.latestSupportedVersion) })
        guard let storeApp, let appVersion = version ?? latestSupportedVersion else {
            let task = Task<AsyncManaged<InstalledApp>, Error> { throw OperationError.appNotFound(name: appName) }
            return (task, progress)
        }
        
        let operation = AppManager.AppOperation.update(installedApp)
        AppManager.shared.set(progress, for: operation)
        
        let installationHandler = { (bundleID: String) in
            if bundleID == StoreApp.altstoreAppID
            {
                DispatchQueue.main.async {
                    // AltStore will quit before installation finishes,
                    // so assume if we get this far the update will finish successfully.
                    let event = AnalyticsManager.Event.updatedApp(installedApp)
                    AnalyticsManager.shared.trackEvent(event)
                }
            }
            
            beginInstallationHandler?(bundleID)
        }
                
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.withValues(bundleID: bundleID, progress: progress, presentingViewController: presentingViewController, beginInstallationHandler: installationHandler) {
                do
                {
                    let installedApp = try await self.install(storeApp, preferredVersion: appVersion, presentingViewController: presentingViewController, operation: operation)
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
        
        return (task, progress)
    }
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    func install(@AsyncManaged _ storeApp: StoreApp,
                 preferredVersion: AltStoreCore.AppVersion?,
                 presentingViewController: UIViewController?,
                 operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        // Verify pledge
        try await self.verifyPledge(for: storeApp, presentingViewController: presentingViewController)
        
        // Verify version is supported
        @AsyncManaged
        var appVersion: AltStoreCore.AppVersion
        
        if let preferredVersion
        {
            appVersion = preferredVersion
        }
        else
        {
            guard let latestAppVersion = await $storeApp.latestAvailableVersion else {
                let failureReason = await String(format: NSLocalizedString("The latest version of %@ could not be determined.", comment: ""), $storeApp.name)
                throw OperationError.unknown(failureReason: failureReason) //TODO: Make proper error case
            }
            
            appVersion = latestAppVersion
        }
        
        do
        {
            // Verify app version is supported
            try await $storeApp.perform { _ in
                try self.verify(appVersion)
            }
        }
        catch let error as VerificationError where error.code == .iOSVersionNotSupported
        {
            guard let presentingViewController, let latestSupportedVersion = await $storeApp.latestSupportedVersion else { throw error }
            
            try await $storeApp.perform { storeApp in
                if let installedApp = storeApp.installedApp
                {
                    guard !installedApp.matches(latestSupportedVersion) else { throw error }
                }
            }
            
            let title = NSLocalizedString("Unsupported iOS Version", comment: "")
            let message = error.localizedDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
            let localizedVersion = await $storeApp.perform { _ in latestSupportedVersion.localizedVersion }
            
            let action = await UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), $storeApp.name, localizedVersion), style: .default)
            try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
            
            appVersion = latestSupportedVersion
        }
        
        if await $storeApp.bundleIdentifier != StoreApp.altstoreAppID
        {
            do
            {
                // Verify hosted ADP matches source
                try await self.verifyRemoteADP(for: appVersion)
            }
            catch let error as OperationError where error.code == .pledgeRequired
            {
                guard let presentingViewController else { throw error }
                
                // Attempt to sign-in again in case our Patreon session has expired.
                try await withCheckedThrowingContinuation { continuation in
                    PatreonAPI.shared.authenticate(presentingViewController: presentingViewController) { result in
                        do
                        {
                            let account = try result.get()
                            try account.managedObjectContext?.save()
                            
                            continuation.resume()
                        }
                        catch
                        {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                // Success, so try to verify ADP again.
                try await self.verifyRemoteADP(for: appVersion)
            }
        }
        
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
    
    nonisolated func verify(_ appVersion: AltStoreCore.AppVersion) throws
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
    
    func verifyRemoteADP(@AsyncManaged for appVersion: AltStoreCore.AppVersion) async throws
    {
        let (appName, bundleID, marketplaceID, version, buildVersion, sourceID, sourceURL) = await $appVersion.perform {
            ($0.storeApp?.name, $0.appBundleID, $0.storeApp?._marketplaceID, $0.version, $0.buildVersion, $0.storeApp?.sourceIdentifier, $0.storeApp?.source?.sourceURL)
        }
        
        guard let marketplaceID else { throw OperationError.unknownMarketplaceID(appName: appName ?? bundleID) }
        
        do
        {
            let adp = try await self.fetchADPManifest(for: appVersion)

            do
            {
                guard bundleID == adp.bundleId else { throw VerificationError.mismatchedBundleID(bundleID, expectedBundleID: adp.bundleId, app: appVersion) }
                guard marketplaceID == adp.appleItemId else { throw VerificationError.mismatchedMarketplaceID(marketplaceID, expectedMarketplaceID: adp.appleItemId, app: appVersion) }
                
                guard version == adp.shortVersionString else { throw VerificationError.mismatchedVersion(version, expectedVersion: adp.shortVersionString, app: appVersion) }
                
                guard let buildVersion else { throw VerificationError.mismatchedBuildVersion("", expectedVersion: adp.bundleVersion, app: appVersion) }
                guard buildVersion == adp.bundleVersion else { throw VerificationError.mismatchedBuildVersion(buildVersion, expectedVersion: adp.bundleVersion, app: appVersion) }
            }
            catch let error as VerificationError
            {
                switch (bundleID, version)
                {
                // Ignore verification errors for grandfathered-in apps + versions.
                case ("io.altstore.AltStore", "2.1.1"), ("io.altstore.AltStore", "2.1.2"): break
                case ("com.rileytestut.Delta", "1.6.2"): break
                case ("com.rileytestut.Delta.Beta", "1.6.2b"): break
                case ("com.rileytestut.Clip", "1.1"): break
                case ("com.rileytestut.Clip.Beta", "1.2b"): break
                case ("MikeMichael225.qBitControl", "1.2"): break
                
                // Throw error for all other apps/versions.
                default: throw error
                }
            }
            
            let expectedSourceURL: URL?
            switch bundleID
            {
            case "com.xitrix.iTorrent2": expectedSourceURL = URL(string: "https://xitrix.github.io/iTorrent/AltStoreEU.json")!
            case "MikeMichael225.qBitControl": expectedSourceURL = URL(string: "https://raw.githubusercontent.com/michael-128/qbitcontrol-releases/main/source.json")!
            default: expectedSourceURL = nil
            }
            
            // Ensure source ID matches expected source ID.
            if let sourceURL, let sourceID, let expectedSourceURL
            {
                let expectedSourceID = try! expectedSourceURL.normalized()
                if sourceID != expectedSourceID
                {
                    // Source does not match expected source, so check if new source is recommended (visible or not).
                    if let recommendedSources = UserDefaults.shared.recommendedSources, recommendedSources.contains(where: { $0.identifier == sourceID })
                    {
                        // Source is recommended, so allow installation.
                    }
                    else
                    {
                        // Assume source is unofficial, so block installation.
                        throw VerificationError.incorrectSource(sourceURL: sourceURL, expectedSourceURL: expectedSourceURL, app: appVersion)
                    }
                }
            }
        }
        catch
        {
            let appName = appName ?? NSLocalizedString("App", comment: "")
            let localizedTitle = String(format: NSLocalizedString("Failed to Verify %@", comment: ""), appName)
            
            let nsError = (error as NSError).withLocalizedTitle(localizedTitle)
            throw nsError
        }
    }
    
    func _install(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        @AsyncManaged
        var storeApp: StoreApp
        
        guard let _app = await $appVersion.app else {
            let failureReason = NSLocalizedString("The app listing could not be found.", comment: "")
            throw OperationError.unknown(failureReason: failureReason)
        }
        storeApp = _app
        
        guard let marketplaceID = await $storeApp.marketplaceID else {
            throw await OperationError.unknownMarketplaceID(appName: $storeApp.name)
        }
        
        // Can't rely on localApp.isInstalled to be accurate... FB://FB14080494
        // let isInstalled = await localApp.isInstalled
        // let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
        
        let installedApps = await AppLibrary.current.installedApps
        let isInstalled = installedApps.contains(where: { $0.id == marketplaceID })
        
        let bundleID = await $storeApp.bundleIdentifier
        InstallTaskContext.beginInstallationHandler?(bundleID) // TODO: Is this called too early?
        
        guard bundleID != StoreApp.altstoreAppID else {
            // MarketplaceKit doesn't support updating marketplaces themselves (🙄)
            // so we have to ask user to manually update AltStore via Safari.
            // TODO: Figure out how to handle beta AltStore
            
            await MainActor.run {
                let openURL = URL(string: "https://altstore.io/update-pal")!
                UIApplication.shared.open(openURL)
            }
            
            // Cancel installation and let user manually update.
            throw CancellationError()
        }
                
        let installMarketplaceAppViewController = await MainActor.run { [operation] () -> InstallMarketplaceAppViewController? in
            
            var action: AppBannerView.AppAction?
            var isRedownload: Bool = false
            
            switch operation
            {
            case .install(let app):
                guard let storeApp = app.storeApp else { break }
                action = .install(storeApp)
                isRedownload = isInstalled // "redownload" if app is already installed
                
            case .update(let app):
                guard let installedApp = app as? InstalledApp ?? app.storeApp?.installedApp else { break }
                action = .update(installedApp)
                isRedownload = false // Updates are never redownloads
                
            default: break
            }
            
            guard let action else { return nil }
            
            let installMarketplaceAppViewController = InstallMarketplaceAppViewController(action: action, isRedownload: isRedownload)
            return installMarketplaceAppViewController
        }
        
        if let installMarketplaceAppViewController
        {
            // Retrieve InstallTaskContext.presentingViewController now because it will be nil in the DispatchQueue.main.async call.
            guard let presentingViewController = await InstallTaskContext.presentingViewController else {
                throw OperationError.unknown(failureReason: NSLocalizedString("Could not determine presenting context.", comment: ""))
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
                DispatchQueue.main.async {
                    installMarketplaceAppViewController.completionHandler = { result in
                        continuation.resume(with: result)
                    }
                    
                    let navigationController = UINavigationController(rootViewController: installMarketplaceAppViewController)
                    presentingViewController.present(navigationController, animated: true)
                }
            }
        }
        
        #if !DEBUG
        
        var didAddChildProgress = false
        
        while true
        {
            // Wait until app is finished installing...
            
            let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
            
            let (isInstalled, installation, installedMetadata) = await MainActor.run {
                // isInstalled is not reliable, but we use it for logging purposes.
                (localApp.isInstalled, localApp.installation, localApp.installedMetadata)
            }
                        
            Logger.sideload.info("Installing app \(bundleID, privacy: .public)... Installed: \(isInstalled). Metadata: \(String(describing: installedMetadata), privacy: .public). Installation: \(String(describing: installation), privacy: .public)")
                                    
            if let installation
            {
                // App is currently being installed.
                Logger.sideload.info("App \(bundleID, privacy: .public) has valid installation metadata!")
                
                guard installation.progress.fractionCompleted >= 0 && installation.progress.completedUnitCount >= 0 else {
                    Logger.sideload.info("Installation progress for \(bundleID, privacy: .public) is negative, polling until valid progress...")
                    
                    // Poll until we receive a valid progress object.
                    try await Task.sleep(for: .milliseconds(50))
                    continue
                }
                
                if !didAddChildProgress
                {
                    Logger.sideload.info("Added child progress for app \(bundleID, privacy: .public)")
                    
                    InstallTaskContext.progress.addChild(installation.progress, withPendingUnitCount: InstallTaskContext.progress.totalUnitCount)
                    didAddChildProgress = true
                }
                
                if installation.progress.fractionCompleted != 1.0
                {
                    // Progress has not yet completed, so add it as child and wait for it to complete.
                    
                    Logger.sideload.info("Installation progress for \(bundleID, privacy: .public) is less than 1.0, polling until finished...")
                    
                    var fractionComplete: Double?
                    
                    while true
                    {
                        if installation.progress.isCancelled
                        {
                            // Installation was cancelled, so assume error occured.
                            Logger.sideload.info("Installation cancelled for \(bundleID, privacy: .public)! \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                            throw CancellationError()
                        }
                        
                        if installation.progress.fractionCompleted == 1.0
                        {
                            Logger.sideload.info("Installation of \(bundleID, privacy: .public) finished with progress: \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                            break
                        }
                        
                        if let fractionComplete, installation.progress.fractionCompleted != fractionComplete
                        {
                            // If fractionComplete has changed at least once but the value is negative, consider it complete.
                            if installation.progress.fractionCompleted < 0 || installation.progress.completedUnitCount < 0
                            {
                                Logger.sideload.fault("Installation progress for \(bundleID, privacy: .public) returned invalid value! \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                                break
                            }
                        }
                        
                        fractionComplete = installation.progress.fractionCompleted
                        
                        if installation.progress.fractionCompleted < 0 || installation.progress.completedUnitCount < 0
                        {
                            // One last sanity check: if progress is negative, check if AppLibrary _does_ report correct value.
                            // If it does, we can exit early.
                            Logger.sideload.info("Negative installation progress for \(bundleID, privacy: .public): \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                            
                            let didInstallSuccessfully = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                            if didInstallSuccessfully
                            {
                                break
                            }
                        }
                        
                        Logger.sideload.info("Installation progress for \(bundleID, privacy: .public): \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                        
                        // I hate that this is the best way to _reliably_ know when app finished installing...but it is.
                        try await Task.sleep(for: .seconds(0.5))
                    }
                }
                
                if UserDefaults.shared.shouldManageInstalledApps
                {
                    let didInstallSuccessfully = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                    guard didInstallSuccessfully || installation.progress.fractionCompleted >= 1 else {
                        // Install progress is less than 100%, _and_ app version does not match the version we attempted to install, so assume error occured.
                        throw CancellationError()
                    }
                }
                
                // App version matches version we're installing, so break loop.
                Logger.sideload.info("Finished installing marketplace app \(bundleID, privacy: .public)")
                
                break
            }
            else
            {
                Logger.sideload.info("App \(bundleID, privacy: .public) is missing installation metadata, falling back to manual check.")
                
                let isVersionInstalled = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                if !isVersionInstalled
                {
                    // App version is not installed...supposedly.
                    
                    if !isInstalled && !UserDefaults.shared.shouldManageInstalledApps
                    {
                        // App itself apparently isn't installed, but check if we can open URL as fallback.
                        
                        if let openURL = await $storeApp._installedOpenURL, await UIApplication.shared.canOpenURL(openURL)
                        {
                            Logger.sideload.info("Fallback Open URL check for \(bundleID, privacy: .public) succeeded, assuming installation finished successfully.")
                        }
                        else
                        {
                            try await Task.sleep(for: .milliseconds(50))
                            continue
                        }
                    }
                    else
                    {
                        // App is either not installed, or installed version doesn't match the version we're installing,
                        // Either way, keep polling.
                                            
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                }
                
                if !didAddChildProgress
                {
                    // Make sure we manually set progress as completed.
                    Logger.sideload.info("Manually updated progress for app \(bundleID, privacy: .public) to \(InstallTaskContext.progress.fractionCompleted) (\(InstallTaskContext.progress.completedUnitCount) of \(InstallTaskContext.progress.totalUnitCount))")
                    InstallTaskContext.progress.completedUnitCount = InstallTaskContext.progress.totalUnitCount
                }
                
                // App is installed, break loop.
                Logger.sideload.info("(Apparently) finished installing marketplace app \(bundleID, privacy: .public) (with manual check)")
                break
            }
        }
        
        #endif
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        let installedApp = await backgroundContext.performAsync {
            
            let storeApp = backgroundContext.object(with: storeApp.objectID) as! StoreApp
            let appVersion = backgroundContext.object(with: appVersion.objectID) as! AltStoreCore.AppVersion
            
            let installedApp = self.makeInstalledApp(for: storeApp, appVersion: appVersion, in: backgroundContext)
            return installedApp
        }
        
        return AsyncManaged(wrappedValue: installedApp)
    }
    
    func makeInstalledApp(for storeApp: StoreApp, appVersion: AltStoreCore.AppVersion, in context: NSManagedObjectContext) -> InstalledApp
    {
        /* App */
        let installedApp: InstalledApp
        
        // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), storeApp.bundleIdentifier)
        if let app = InstalledApp.first(satisfying: predicate, in: context)
        {
            installedApp = app
        }
        else
        {
            installedApp = InstalledApp(marketplaceApp: storeApp, context: context)
        }
        
        installedApp.update(forMarketplaceAppVersion: appVersion)
        
        //TODO: Include app extensions?
        
        return installedApp
    }
    
    func isAppVersionInstalled(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, @AsyncManaged for storeApp: StoreApp) async throws -> Bool
    {
        guard let marketplaceID = await $storeApp.marketplaceID else {
            throw await OperationError.unknownMarketplaceID(appName: $storeApp.name)
        }
        
        // First, check that the app is installed in the first place.
        let isInstalled = await AppLibrary.current.installedApps.contains(where: { $0.id == marketplaceID })
        guard isInstalled else { return false }
        
        let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
        let bundleID = await $storeApp.bundleIdentifier
        
        if let installedMetadata = await localApp.installedMetadata
        {
            // Verify installed metadata matches expected version.

            let (version, buildVersion) = await $appVersion.perform { ($0.version, $0.buildVersion) }
            if version == installedMetadata.shortVersion && buildVersion == installedMetadata.version
            {
                // Installed version matches storeApp version.
                return true
            }
            else
            {
                // Installed version does NOT match the version we're installing.
                Logger.sideload.info("App \(bundleID, privacy: .public) is installed, but does not match the version we're expecting. Expected: \(version) (\(buildVersion ?? "")). Actual: \(installedMetadata.shortVersion) (\(installedMetadata.version))")
                return false
            }
        }
        else
        {
            // App is installed, but has no installedMetadata...
            // This is most likely a bug, but we still have to handle it.
            // Assume this only happens during initial install.
            
            Logger.sideload.error("App \(bundleID, privacy: .public) is installed, but installedMetadata is nil. Assuming this is a new installation (or that the update completes successfully).")
            return true
        }
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func redeemPALPromo(session: String, emailAddress: String) async throws
    {
        let requestURL = AppMarketplace.requestBaseURL.appendingPathComponent("pal-promo")
        
        let payload = PALPromoRequest(session: session, email: emailAddress)
        let bodyData = try JSONEncoder().encode(payload)
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let response = try await self.send(request, pinCertificates: true, expecting: PALPromoResponse.self)
        
        Keychain.shared.stripeEmailAddress = emailAddress
        Keychain.shared.palPromoExpiration = response.promoExpiration
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func requestInstallToken(bundleID: String, isRedownload: Bool) async throws -> String
    {
        let requestURL = AppMarketplace.requestBaseURL.appendingPathComponent("install-token")
        
        let payload = InstallVerificationTokenRequest(bundleID: bundleID, redownload: isRedownload)
        let bodyData = try JSONEncoder().encode(payload)
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let response = try await self.send(request, expecting: InstallVerificationTokenResponse.self)
        return response.token
    }
    
    private func fetchADPManifest(@AsyncManaged for appVersion: AltStoreCore.AppVersion) async throws -> ADPManifest
    {
        let (downloadURL, assetURLs, appName, isPledgeRequired) = try await $appVersion.perform { (appVersion) in
            guard let storeApp = appVersion.storeApp else { throw OperationError.invalidApp() }
            return (appVersion.downloadURL, appVersion.assetURLs, storeApp.name, storeApp.isPledgeRequired)
        }
        
        let manifestURL: URL
        if let assetURL = assetURLs?["manifest"]
        {
            manifestURL = assetURL
        }
        else if downloadURL.absoluteString.lowercased().contains("patreon.com/posts/")
        {
            manifestURL = try await self.manifestURL(forPatreonPost: downloadURL)
        }
        else
        {
            manifestURL = downloadURL.appending(path: "manifest.json")
        }
        
        let isPatreonURL = manifestURL.absoluteString.lowercased().contains("patreon.com")
        let request = URLRequest(url: manifestURL)
        
        do
        {
            let adp = try await self.send(request, expecting: ADPManifest.self)
            return adp
        }
        catch let error as URLError where isPatreonURL && isPledgeRequired
        {
            switch error.code
            {
            case .noPermissionsToReadFile, .badServerResponse:
                // Patreon URL and app requires pledge, so assume this error means we need to be re-authenticated.
                throw OperationError.pledgeRequired(appName: appName)
                
            default: throw error
            }
        }
    }
    
    private func manifestURL(forPatreonPost postURL: URL) async throws -> URL
    {
        var postLink = postURL.absoluteString
        
        // Remove trailing "/" if there is one.
        if postLink.hasSuffix("/")
        {
            postLink.removeLast()
        }
        
        guard let lastNonDigitIndex = postLink.lastIndex(where: { !$0.isNumber }) else {
            throw OperationError.unknown(failureReason: NSLocalizedString("Unable to parse Patreon post URL.", comment: ""))
        }
        
        // Assume everything after the last non-digit character (most likely `-` or `/`) is the post's ID
        let index = postLink.index(after: lastNonDigitIndex)
        let postID = String(postLink[index...])
        
        let allMedia = try await PatreonAPI.shared.fetchPostMedia(postID: postID)
        guard let media = allMedia.first(where: { $0.filename.lowercased() == "manifest.json" }) else {
            throw OperationError.unknown(failureReason: NSLocalizedString("Failed to retrieve manifest.json URL from Patreon post.", comment: ""))
        }
        
        // Construct download URL based on standard Patreon format.
        let downloadURL = URL(string: "https://www.patreon.com/file?h=\(postID)&m=\(media.identifier)")!
        return downloadURL
    }
    
    private func send<T: Decodable>(_ request: URLRequest, pinCertificates: Bool = false, expecting: T.Type) async throws -> T
    {
        let session = pinCertificates ? URLSession(configuration: .sharedCookies, delegate: self, delegateQueue: nil) : self.session
        
        let (data, urlResponse) = try await session.data(for: request)
        guard let requestURL = request.url, let httpResponse = urlResponse as? HTTPURLResponse else { throw OperationError.unknown() }
        
        guard httpResponse.statusCode == 200 else { throw URLError(.badServerResponse, userInfo: [NSURLErrorKey: requestURL, NSURLErrorFailingURLErrorKey: requestURL]) }
        
        let decoder = Foundation.JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let response = try decoder.decode(T.self, from: data)
        return response
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
            
            // DON'T schedule expiration warning for Marketplace version.
            // if installedApp.bundleIdentifier == StoreApp.altstoreAppID
            // {
            //     AppManager.shared.scheduleExpirationWarningLocalNotification(for: installedApp)
            // }
            
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

@available(iOS 17.4, *)
extension AppMarketplace: URLSessionDelegate
{
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        guard 
            let trust = challenge.protectionSpace.serverTrust,
            let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let certificate = certificates.first
        else { return (.cancelAuthenticationChallenge, nil) }
        
        var commonName: CFString?
        let status = SecCertificateCopyCommonName(certificate, &commonName)
        guard status == 0 else {
            Logger.main.error("Unknown common name for SSL certificate, rejecting challenge.")
            return (.cancelAuthenticationChallenge, nil)
        }
        
        // Ensure certificate is a known pinned certificate.
        guard let name = commonName as? String, name == "altstore.io" else {
            Logger.main.error("Attempting server connection with unknown certificate, rejecting challenge.")
            return (.cancelAuthenticationChallenge, nil)
        }
        
        return (.useCredential, URLCredential(trust: trust))
    }
}
