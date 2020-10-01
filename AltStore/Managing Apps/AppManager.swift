//
//  AppManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import UIKit
import UserNotifications
import MobileCoreServices
import Intents
import Combine
import WidgetKit

import AltStoreCore
import AltSign
import Roxas

extension AppManager
{
    static let didFetchSourceNotification = Notification.Name("com.altstore.AppManager.didFetchSource")
    
    static let expirationWarningNotificationID = "altstore-expiration-warning"
}

@available(iOS 13, *)
class AppManagerPublisher: ObservableObject
{
    @Published
    fileprivate(set) var installationProgress = [String: Progress]()
    
    @Published
    fileprivate(set) var refreshProgress = [String: Progress]()
}

class AppManager
{
    static let shared = AppManager()
    
    @available(iOS 13, *)
    private(set) lazy var publisher: AppManagerPublisher = AppManagerPublisher()
    
    private let operationQueue = OperationQueue()
    private let serialOperationQueue = OperationQueue()

    private var installationProgress = [String: Progress]() {
        didSet {
            guard #available(iOS 13, *) else { return }
            self.publisher.installationProgress = self.installationProgress
        }
    }
    private var refreshProgress = [String: Progress]() {
        didSet {
            guard #available(iOS 13, *) else { return }
            self.publisher.refreshProgress = self.refreshProgress
        }
    }
    
    @available(iOS 13.0, *)
    private lazy var cancellables = Set<AnyCancellable>()
    
    private init()
    {
        self.operationQueue.name = "com.altstore.AppManager.operationQueue"
        
        self.serialOperationQueue.name = "com.altstore.AppManager.serialOperationQueue"
        self.serialOperationQueue.maxConcurrentOperationCount = 1
        
        if #available(iOS 13, *)
        {
            self.prepareSubscriptions()
        }
    }
    
    @available(iOS 13, *)
    func prepareSubscriptions()
    {
        /// Every time refreshProgress is changed, update all InstalledApps in memory
        /// so that app.isRefreshing == refreshProgress.keys.contains(app.bundleID)
        
        self.publisher.$refreshProgress
            .receive(on: RunLoop.main)
            .map(\.keys)
            .flatMap { (bundleIDs) in
                DatabaseManager.shared.viewContext.registeredObjects.publisher
                    .compactMap { $0 as? InstalledApp }
                    .map { ($0, bundleIDs.contains($0.bundleIdentifier)) }
            }
            .sink { (installedApp, isRefreshing) in
                installedApp.isRefreshing = isRefreshing
            }
            .store(in: &self.cancellables)
    }
}

extension AppManager
{
    func update()
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            #if targetEnvironment(simulator)
            // Apps aren't ever actually installed to simulator, so just do nothing rather than delete them from database.
            #else
            do
            {
                let installedApps = InstalledApp.all(in: context)
                
                if UserDefaults.standard.legacySideloadedApps == nil
                {
                    // First time updating apps since updating AltStore to use custom UTIs,
                    // so cache all existing apps temporarily to prevent us from accidentally
                    // deleting them due to their custom UTI not existing (yet).
                    let apps = installedApps.map { $0.bundleIdentifier }
                    UserDefaults.standard.legacySideloadedApps = apps
                }
                
                let legacySideloadedApps = Set(UserDefaults.standard.legacySideloadedApps ?? [])
                
                for app in installedApps
                {
                    guard app.bundleIdentifier != StoreApp.altstoreAppID else {
                        self.scheduleExpirationWarningLocalNotification(for: app)
                        continue
                    }
                    
                    guard !self.isActivelyManagingApp(withBundleID: app.bundleIdentifier) else { continue }
                    
                    if !UserDefaults.standard.isLegacyDeactivationSupported
                    {
                        // We can't (ab)use provisioning profiles to deactivate apps,
                        // which means we must delete apps to free up active slots.
                        // So, only check if active apps are installed to prevent
                        // false positives when checking inactive apps.
                        guard app.isActive else { continue }
                    }
                    
                    let uti = UTTypeCopyDeclaration(app.installedAppUTI as CFString)?.takeRetainedValue() as NSDictionary?
                    if uti == nil && !legacySideloadedApps.contains(app.bundleIdentifier)
                    {
                        // This UTI is not declared by any apps, which means this app has been deleted by the user.
                        // This app is also not a legacy sideloaded app, so we can assume it's fine to delete it.
                        context.delete(app)
                    }
                }
                
                try context.save()
            }
            catch
            {
                print("Error while fetching installed apps.", error)
            }
            #endif
            
            do
            {
                let installedAppBundleIDs = InstalledApp.all(in: context).map { $0.bundleIdentifier }
                                
                let cachedAppDirectories = try FileManager.default.contentsOfDirectory(at: InstalledApp.appsDirectoryURL,
                                                                                       includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                                                       options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
                for appDirectory in cachedAppDirectories
                {
                    do
                    {
                        let resourceValues = try appDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                        guard let isDirectory = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                        
                        if isDirectory && !installedAppBundleIDs.contains(bundleID) && !self.isActivelyManagingApp(withBundleID: bundleID)
                        {
                            print("DELETING CACHED APP:", bundleID)
                            try FileManager.default.removeItem(at: appDirectory)
                        }
                    }
                    catch
                    {
                        print("Failed to remove cached app directory.", error)
                    }
                }
            }
            catch
            {
                print("Failed to remove cached apps.", error)
            }
        }
    }
    
    @discardableResult
    func findServer(context: OperationContext = OperationContext(), completionHandler: @escaping (Result<Server, Error>) -> Void) -> FindServerOperation
    {
        let findServerOperation = FindServerOperation(context: context)
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let server): context.server = server
            }
        }
        
        self.run([findServerOperation], context: context)
        
        return findServerOperation
    }
    
    @discardableResult
    func authenticate(presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<(ALTTeam, ALTCertificate, ALTAppleAPISession), Error>) -> Void) -> AuthenticationOperation
    {
        if let operation = context.authenticationOperation
        {
            return operation
        }
        
        let findServerOperation = self.findServer(context: context) { _ in }
        
        let authenticationOperation = AuthenticationOperation(context: context, presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success: break
            }
            
            completionHandler(result)
        }
        authenticationOperation.addDependency(findServerOperation)
        
        self.run([authenticationOperation], context: context)
        
        return authenticationOperation
    }
}

extension AppManager
{
    func fetchSource(sourceURL: URL, completionHandler: @escaping (Result<Source, Error>) -> Void)
    {
        let fetchSourceOperation = FetchSourceOperation(sourceURL: sourceURL)
        fetchSourceOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success(let source):
                completionHandler(.success(source))
            }
        }
        
        self.run([fetchSourceOperation], context: nil)
    }
    
    func fetchSources(completionHandler: @escaping (Result<(Set<Source>, NSManagedObjectContext), FetchSourcesError>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let sources = Source.all(in: context)
            guard !sources.isEmpty else { return completionHandler(.failure(.init(OperationError.noSources))) }
            
            let dispatchGroup = DispatchGroup()
            var fetchedSources = Set<Source>()
            
            var errors = [Source: Error]()
            
            let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            let operations = sources.map { (source) -> FetchSourceOperation in
                dispatchGroup.enter()
                
                let fetchSourceOperation = FetchSourceOperation(sourceURL: source.sourceURL, managedObjectContext: managedObjectContext)
                fetchSourceOperation.resultHandler = { (result) in
                    switch result
                    {
                    case .success(let source): fetchedSources.insert(source)
                    case .failure(let error):
                        let source = managedObjectContext.object(with: source.objectID) as! Source
                        source.error = (error as NSError).sanitizedForCoreData()
                        errors[source] = error
                    }
                    
                    dispatchGroup.leave()
                }
                
                return fetchSourceOperation
            }
            
            dispatchGroup.notify(queue: .global()) {
                managedObjectContext.perform {
                    if !errors.isEmpty
                    {
                        let sources = Set(sources.compactMap { managedObjectContext.object(with: $0.objectID) as? Source })
                        completionHandler(.failure(.init(sources: sources, errors: errors, context: managedObjectContext)))
                    }
                    else
                    {
                        completionHandler(.success((fetchedSources, managedObjectContext)))
                    }
                }
                
                NotificationCenter.default.post(name: AppManager.didFetchSourceNotification, object: self)
            }
            
            self.run(operations, context: nil)
        }
    }
    
    func fetchAppIDs(completionHandler: @escaping (Result<([AppID], NSManagedObjectContext), Error>) -> Void)
    {
        let authenticationOperation = self.authenticate(presentingViewController: nil) { (result) in
            print("Authenticated for fetching App IDs with result:", result)
        }
        
        let fetchAppIDsOperation = FetchAppIDsOperation(context: authenticationOperation.context)
        fetchAppIDsOperation.resultHandler = completionHandler
        fetchAppIDsOperation.addDependency(authenticationOperation)
        self.run([fetchAppIDsOperation], context: authenticationOperation.context)
    }
    
    @discardableResult
    func install<T: AppProtocol>(_ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.install(app)
        self.perform([operation], presentingViewController: presentingViewController, group: group)
        
        return group.progress
    }
    
    @discardableResult
    func update(_ app: InstalledApp, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        guard let storeApp = app.storeApp else {
            completionHandler(.failure(OperationError.appNotFound))
            return Progress.discreteProgress(totalUnitCount: 1)
        }
        
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.update(storeApp)
        assert(operation.app as AnyObject === storeApp) // Make sure we never accidentally "update" to already installed app.
        
        self.perform([operation], presentingViewController: presentingViewController, group: group)
        
        return group.progress
    }
    
    @discardableResult
    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup? = nil) -> RefreshGroup
    {
        let group = group ?? RefreshGroup()
        
        let operations = installedApps.map { AppOperation.refresh($0) }
        return self.perform(operations, presentingViewController: presentingViewController, group: group)
    }
    
    func activate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        let group = RefreshGroup()
        
        let operation = AppOperation.activate(installedApp)
        self.perform([operation], presentingViewController: presentingViewController, group: group)
        
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown }
                
                let installedApp = try result.get()
                assert(installedApp.managedObjectContext != nil)
                
                installedApp.managedObjectContext?.perform {
                    installedApp.isActive = true
                    completionHandler(.success(installedApp))
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func deactivate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        if UserDefaults.standard.isLegacyDeactivationSupported
        {
            // Normally we pipe everything down into perform(),
            // but the pre-iOS 13.5 deactivation method doesn't require
            // authentication, so we keep it separate.
            let context = OperationContext()
            
            let findServerOperation = self.findServer(context: context) { _ in }
            
            let deactivateAppOperation = DeactivateAppOperation(app: installedApp, context: context)
            deactivateAppOperation.resultHandler = { (result) in
                completionHandler(result)
            }
            deactivateAppOperation.addDependency(findServerOperation)
            
            self.run([deactivateAppOperation], context: context, requiresSerialQueue: true)
        }
        else
        {
            let group = RefreshGroup()
            group.completionHandler = { (results) in
                do
                {
                    guard let result = results.values.first else { throw OperationError.unknown }

                    let installedApp = try result.get()
                    assert(installedApp.managedObjectContext != nil)
                    
                    installedApp.managedObjectContext?.perform {
                        completionHandler(.success(installedApp))
                    }
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
            
            let operation = AppOperation.deactivate(installedApp)
            self.perform([operation], presentingViewController: presentingViewController, group: group)
        }
    }
    
    func backup(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        let group = RefreshGroup()
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown }
                
                let installedApp = try result.get()
                assert(installedApp.managedObjectContext != nil)
                
                installedApp.managedObjectContext?.perform {
                    completionHandler(.success(installedApp))
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.backup(installedApp)
        self.perform([operation], presentingViewController: presentingViewController, group: group)
    }
    
    func restore(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        let group = RefreshGroup()
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown }
                
                let installedApp = try result.get()
                assert(installedApp.managedObjectContext != nil)
                
                installedApp.managedObjectContext?.perform {
                    installedApp.isActive = true
                    completionHandler(.success(installedApp))
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.restore(installedApp)
        self.perform([operation], presentingViewController: presentingViewController, group: group)
    }
    
    func remove(_ installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let authenticationContext = AuthenticatedOperationContext()
        let appContext = InstallAppOperationContext(bundleIdentifier: installedApp.bundleIdentifier, authenticatedContext: authenticationContext)
        appContext.installedApp = installedApp

        let removeAppOperation = RSTAsyncBlockOperation { (operation) in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                context.delete(installedApp)
                
                do { try context.save() }
                catch { appContext.error = error }
                
                operation.finish()
            }
        }
        
        let removeAppBackupOperation = RemoveAppBackupOperation(context: appContext)
        removeAppBackupOperation.resultHandler = { (result) in
            switch result
            {
            case .success: break
            case .failure(let error): print("Failed to remove app backup.", error)
            }
            
            // Throw the error from removeAppOperation,
            // since that's the error we really care about.
            if let error = appContext.error
            {
                completionHandler(.failure(error))
            }
            else
            {
                completionHandler(.success(()))
            }
        }
        removeAppBackupOperation.addDependency(removeAppOperation)
        
        self.run([removeAppOperation, removeAppBackupOperation], context: authenticationContext)
    }
    
    func installationProgress(for app: AppProtocol) -> Progress?
    {
        let progress = self.installationProgress[app.bundleIdentifier]
        return progress
    }
    
    func refreshProgress(for app: AppProtocol) -> Progress?
    {
        let progress = self.refreshProgress[app.bundleIdentifier]
        return progress
    }
}

extension AppManager
{
    func backgroundRefresh(_ installedApps: [InstalledApp], presentsNotifications: Bool = true, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void)
    {
        let backgroundRefreshAppsOperation = BackgroundRefreshAppsOperation(installedApps: installedApps)
        backgroundRefreshAppsOperation.resultHandler = completionHandler
        backgroundRefreshAppsOperation.presentsFinishedNotification = presentsNotifications
        self.run([backgroundRefreshAppsOperation], context: nil)
    }
}

private extension AppManager
{
    enum AppOperation
    {
        case install(AppProtocol)
        case update(AppProtocol)
        case refresh(InstalledApp)
        case activate(InstalledApp)
        case deactivate(InstalledApp)
        case backup(InstalledApp)
        case restore(InstalledApp)
        
        var app: AppProtocol {
            switch self
            {
            case .install(let app), .update(let app), .refresh(let app as AppProtocol),
                 .activate(let app as AppProtocol), .deactivate(let app as AppProtocol),
                 .backup(let app as AppProtocol), .restore(let app as AppProtocol):
                return app
            }
        }
        
        var bundleIdentifier: String {
            var bundleIdentifier: String!
            
            if let context = (self.app as? NSManagedObject)?.managedObjectContext
            {
                context.performAndWait { bundleIdentifier = self.app.bundleIdentifier }
            }
            else
            {
                bundleIdentifier = self.app.bundleIdentifier
            }
            
            return bundleIdentifier
        }
    }
    
    func isActivelyManagingApp(withBundleID bundleID: String) -> Bool
    {
        let isActivelyManaging = self.installationProgress.keys.contains(bundleID) || self.refreshProgress.keys.contains(bundleID)
        return isActivelyManaging
    }
    
    @discardableResult
    private func perform(_ operations: [AppOperation], presentingViewController: UIViewController?, group: RefreshGroup) -> RefreshGroup
    {
        let operations = operations.filter { self.progress(for: $0) == nil || self.progress(for: $0)?.isCancelled == true }
        
        for operation in operations
        {
            let progress = Progress.discreteProgress(totalUnitCount: 100)
            self.set(progress, for: operation)
        }
        
        if let viewController = presentingViewController
        {
            group.context.presentingViewController = viewController
        }
        
        /* Authenticate (if necessary) */
        var authenticationOperation: AuthenticationOperation?
        if group.context.session == nil
        {
            authenticationOperation = self.authenticate(presentingViewController: presentingViewController, context: group.context) { (result) in
                switch result
                {
                case .failure(let error): group.context.error = error
                case .success: break
                }
            }
        }
        
        func performAppOperations()
        {
            for operation in operations
            {
                let progress = self.progress(for: operation)
                
                if let progress = progress
                {
                    group.progress.totalUnitCount += 1
                    group.progress.addChild(progress, withPendingUnitCount: 1)
                    
                    if group.context.session != nil
                    {
                        // Finished authenticating, so increase completed unit count.
                        progress.completedUnitCount += 20
                    }
                }
                
                switch operation
                {
                case .install(let app), .update(let app):
                    let installProgress = self._install(app, operation: operation, group: group) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(installProgress, withPendingUnitCount: 80)
                    
                case .activate(let app) where UserDefaults.standard.isLegacyDeactivationSupported: fallthrough
                case .refresh(let app):
                    // Check if backup app is installed in place of real app.
                    let uti = UTTypeCopyDeclaration(app.installedBackupAppUTI as CFString)?.takeRetainedValue() as NSDictionary?
                    if app.certificateSerialNumber != group.context.certificate?.serialNumber || uti != nil || app.needsResign
                    {
                        // Resign app instead of just refreshing profiles because either:
                        // * Refreshing using different certificate
                        // * Backup app is still installed
                        // * App explicitly needs resigning
                        
                        let installProgress = self._install(app, operation: operation, group: group) { (result) in
                            self.finish(operation, result: result, group: group, progress: progress)
                        }
                        progress?.addChild(installProgress, withPendingUnitCount: 80)
                    }
                    else
                    {
                        // Refreshing with same certificate as last time, and backup app isn't still installed,
                        // so we can just refresh provisioning profiles.
                        
                        let refreshProgress = self._refresh(app, operation: operation, group: group) { (result) in
                            self.finish(operation, result: result, group: group, progress: progress)
                        }
                        progress?.addChild(refreshProgress, withPendingUnitCount: 80)
                    }
                    
                case .activate(let app):
                    let activateProgress = self._activate(app, operation: operation, group: group) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(activateProgress, withPendingUnitCount: 80)
                    
                case .deactivate(let app):
                    let deactivateProgress = self._deactivate(app, operation: operation, group: group) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(deactivateProgress, withPendingUnitCount: 80)
                    
                case .backup(let app):
                    let backupProgress = self._backup(app, operation: operation, group: group) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(backupProgress, withPendingUnitCount: 80)
                    
                case .restore(let app):
                    // Restoring, which is effectively just activating an app.
                    
                    let activateProgress = self._activate(app, operation: operation, group: group) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(activateProgress, withPendingUnitCount: 80)
                }
            }
        }
        
        if let authenticationOperation = authenticationOperation
        {
            let awaitAuthenticationOperation = BlockOperation {
                if let managedObjectContext = operations.lazy.compactMap({ ($0.app as? NSManagedObject)?.managedObjectContext }).first
                {
                    managedObjectContext.perform { performAppOperations() }
                }
                else
                {
                    performAppOperations()
                }
            }
            awaitAuthenticationOperation.addDependency(authenticationOperation)
            self.run([awaitAuthenticationOperation], context: group.context, requiresSerialQueue: true)
        }
        else
        {
            performAppOperations()
        }
        
        return group
    }
    
    private func _install(_ app: AppProtocol, operation: AppOperation, group: RefreshGroup, context: InstallAppOperationContext? = nil, additionalEntitlements: [ALTEntitlement: Any]? = nil, cacheApp: Bool = true, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let context = context ?? InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        assert(context.authenticatedContext === group.context)
        
        context.beginInstallationHandler = { (installedApp) in
            switch operation
            {
            case .update where installedApp.bundleIdentifier == StoreApp.altstoreAppID:
                // AltStore will quit before installation finishes,
                // so assume if we get this far the update will finish successfully.
                let event = AnalyticsManager.Event.updatedApp(installedApp)
                AnalyticsManager.shared.trackEvent(event)
                
            default: break
            }
            
            group.beginInstallationHandler?(installedApp)
        }
        
        var downloadingApp = app
        
        if let installedApp = app as? InstalledApp
        {
            if let storeApp = installedApp.storeApp, !FileManager.default.fileExists(atPath: installedApp.fileURL.path)
            {
                // Cached app has been deleted, so we need to redownload it.
                downloadingApp = storeApp
            }
            
            if installedApp.hasAlternateIcon
            {
                context.alternateIconURL = installedApp.alternateIconURL
            }
        }
        
        let downloadedAppURL = context.temporaryDirectory.appendingPathComponent("Cached.app")
        
        /* Download */
        let downloadOperation = DownloadAppOperation(app: downloadingApp, destinationURL: downloadedAppURL, context: context)
        downloadOperation.resultHandler = { (result) in
            do
            {
                let app = try result.get()
                context.app = app
                
                if cacheApp
                {
                    try FileManager.default.copyItem(at: app.fileURL, to: InstalledApp.fileURL(for: app), shouldReplace: true)
                }
            }
            catch
            {
                context.error = error
            }
        }
        progress.addChild(downloadOperation.progress, withPendingUnitCount: 25)
        
        
        /* Verify App */
        let verifyOperation = VerifyAppOperation(context: context)
        verifyOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success: break
            }
        }
        verifyOperation.addDependency(downloadOperation)
        
        
        /* Refresh Anisette Data */
        let refreshAnisetteDataOperation = FetchAnisetteDataOperation(context: group.context)
        refreshAnisetteDataOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let anisetteData): group.context.session?.anisetteData = anisetteData
            }
        }
        refreshAnisetteDataOperation.addDependency(verifyOperation)
        
        
        /* Fetch Provisioning Profiles */
        let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
        fetchProvisioningProfilesOperation.additionalEntitlements = additionalEntitlements
        fetchProvisioningProfilesOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
            }
        }
        fetchProvisioningProfilesOperation.addDependency(refreshAnisetteDataOperation)
        progress.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 5)
        
        
        /* Resign */
        let resignAppOperation = ResignAppOperation(context: context)
        resignAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let resignedApp): context.resignedApp = resignedApp
            }
        }
        resignAppOperation.addDependency(fetchProvisioningProfilesOperation)
        progress.addChild(resignAppOperation.progress, withPendingUnitCount: 20)
        
        
        /* Send */
        let sendAppOperation = SendAppOperation(context: context)
        sendAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let installationConnection): context.installationConnection = installationConnection
            }
        }
        sendAppOperation.addDependency(resignAppOperation)
        progress.addChild(sendAppOperation.progress, withPendingUnitCount: 20)
        
        
        /* Install */
        let installOperation = InstallAppOperation(context: context)
        installOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let installedApp):
                context.installedApp = installedApp
                
                if let app = app as? StoreApp, let storeApp = installedApp.managedObjectContext?.object(with: app.objectID) as? StoreApp
                {
                    installedApp.storeApp = storeApp
                }
                
                if let index = UserDefaults.standard.legacySideloadedApps?.firstIndex(of: installedApp.bundleIdentifier)
                {
                    // No longer a legacy sideloaded app, so remove it from cached list.
                    UserDefaults.standard.legacySideloadedApps?.remove(at: index)
                }
                
                completionHandler(.success(installedApp))
            }
        }
        progress.addChild(installOperation.progress, withPendingUnitCount: 30)
        installOperation.addDependency(sendAppOperation)
        
        let operations = [downloadOperation, verifyOperation, refreshAnisetteDataOperation, fetchProvisioningProfilesOperation, resignAppOperation, sendAppOperation, installOperation]
        group.add(operations)
        self.run(operations, context: group.context)
        
        return progress
    }
    
    private func _refresh(_ app: InstalledApp, operation: AppOperation, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let context = AppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        context.app = ALTApplication(fileURL: app.url)
        
        /* Fetch Provisioning Profiles */
        let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
        fetchProvisioningProfilesOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
            }
        }
        progress.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 60)
        
        /* Refresh */
        let refreshAppOperation = RefreshAppOperation(context: context)
        refreshAppOperation.resultHandler = { (result) in
            switch result
            {
            case .success(let installedApp):
                completionHandler(.success(installedApp))
                
            case .failure(ALTServerError.unknownRequest), .failure(OperationError.appNotFound):
                // Fall back to installation if AltServer doesn't support newer provisioning profile requests,
                // OR if the cached app could not be found and we may need to redownload it.
                app.managedObjectContext?.performAndWait { // Must performAndWait to ensure we add operations before we return.
                    let installProgress = self._install(app, operation: operation, group: group) { (result) in
                        completionHandler(result)
                    }
                    progress.addChild(installProgress, withPendingUnitCount: 40)
                }
                
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
        progress.addChild(refreshAppOperation.progress, withPendingUnitCount: 40)
        refreshAppOperation.addDependency(fetchProvisioningProfilesOperation)
        
        let operations = [fetchProvisioningProfilesOperation, refreshAppOperation]
        group.add(operations)
        self.run(operations, context: group.context)

        return progress
    }
    
    private func _activate(_ app: InstalledApp, operation appOperation: AppOperation, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let restoreContext = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        let appContext = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        
        let installBackupAppProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installBackupAppOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            app.managedObjectContext?.perform {
                guard let self = self else { return }
                
                let progress = self._installBackupApp(for: app, operation: appOperation, group: group, context: restoreContext) { (result) in
                    switch result
                    {
                    case .success(let installedApp): restoreContext.installedApp = installedApp
                    case .failure(let error):
                        restoreContext.error = error
                        appContext.error = error
                    }
                    
                    operation.finish()
                }
                installBackupAppProgress.addChild(progress, withPendingUnitCount: 100)
            }
        }
        progress.addChild(installBackupAppProgress, withPendingUnitCount: 30)
        
        let restoreAppOperation = BackupAppOperation(action: .restore, context: restoreContext)
        restoreAppOperation.resultHandler = { (result) in
            switch result
            {
            case .success: break
            case .failure(let error):
                restoreContext.error = error
                appContext.error = error
            }
        }
        restoreAppOperation.addDependency(installBackupAppOperation)
        progress.addChild(restoreAppOperation.progress, withPendingUnitCount: 15)
        
        let installAppProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installAppOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            app.managedObjectContext?.perform {
                guard let self = self else { return }
                
                let progress = self._install(app, operation: appOperation, group: group, context: appContext) { (result) in
                    switch result
                    {
                    case .success(let installedApp): appContext.installedApp = installedApp
                    case .failure(let error): appContext.error = error
                    }
                    
                    operation.finish()
                }
                installAppProgress.addChild(progress, withPendingUnitCount: 100)
            }
        }
        installAppOperation.addDependency(restoreAppOperation)
        progress.addChild(installAppProgress, withPendingUnitCount: 50)
        
        let cleanUpProgress = Progress.discreteProgress(totalUnitCount: 100)
        let cleanUpOperation = RSTAsyncBlockOperation { (operation) in
            do
            {
                let installedApp = try Result(appContext.installedApp, appContext.error).get()
                
                var result: Result<Void, Error>!
                installedApp.managedObjectContext?.performAndWait {
                    result = Result { try installedApp.managedObjectContext?.save() }
                }
                try result.get()
                
                // Successfully saved, so _now_ we can remove backup.
                
                let removeAppBackupOperation = RemoveAppBackupOperation(context: appContext)
                removeAppBackupOperation.resultHandler = { (result) in
                    installedApp.managedObjectContext?.perform {
                        switch result
                        {
                        case .failure(let error):
                            // Don't report error, since it doesn't really matter.
                            print("Failed to delete app backup.", error)
                            
                        case .success: break
                        }
                        
                        completionHandler(.success(installedApp))
                        operation.finish()
                    }
                }
                cleanUpProgress.addChild(removeAppBackupOperation.progress, withPendingUnitCount: 100)
                
                group.add([removeAppBackupOperation])
                self.run([removeAppBackupOperation], context: group.context)
            }
            catch let error where restoreContext.installedApp != nil
            {
                // Activation failed, but restore app was installed, so remove the app.
                
                // Remove error so operation doesn't quit early,
                restoreContext.error = nil
                
                let removeAppOperation = RemoveAppOperation(context: restoreContext)
                removeAppOperation.resultHandler = { (result) in
                    completionHandler(.failure(error))
                    operation.finish()
                }
                cleanUpProgress.addChild(removeAppOperation.progress, withPendingUnitCount: 100)
                
                group.add([removeAppOperation])
                self.run([removeAppOperation], context: group.context)
            }
            catch
            {
                // Activation failed.
                completionHandler(.failure(error))
                operation.finish()
            }
        }
        cleanUpOperation.addDependency(installAppOperation)
        progress.addChild(cleanUpProgress, withPendingUnitCount: 5)
        
        group.add([installBackupAppOperation, restoreAppOperation, installAppOperation, cleanUpOperation])
        self.run([installBackupAppOperation, installAppOperation, restoreAppOperation, cleanUpOperation], context: group.context)
        
        return progress
    }
    
    private func _deactivate(_ app: InstalledApp, operation appOperation: AppOperation, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        let context = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        
        let installBackupAppProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installBackupAppOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            app.managedObjectContext?.perform {
                guard let self = self else { return }
                
                let progress = self._installBackupApp(for: app, operation: appOperation, group: group, context: context) { (result) in
                    switch result
                    {
                    case .success(let installedApp): context.installedApp = installedApp
                    case .failure(let error): context.error = error
                    }
                    
                    operation.finish()
                }
                installBackupAppProgress.addChild(progress, withPendingUnitCount: 100)
            }
        }
        progress.addChild(installBackupAppProgress, withPendingUnitCount: 70)
                    
        let backupAppOperation = BackupAppOperation(action: .backup, context: context)
        backupAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success: break
            }
        }
        backupAppOperation.addDependency(installBackupAppOperation)
        progress.addChild(backupAppOperation.progress, withPendingUnitCount: 15)
        
        let removeAppOperation = RemoveAppOperation(context: context)
        removeAppOperation.resultHandler = { (result) in
            completionHandler(result)
        }
        removeAppOperation.addDependency(backupAppOperation)
        progress.addChild(removeAppOperation.progress, withPendingUnitCount: 15)
        
        group.add([installBackupAppOperation, backupAppOperation, removeAppOperation])
        self.run([installBackupAppOperation, backupAppOperation, removeAppOperation], context: group.context)
        
        return progress
    }
    
    private func _backup(_ app: InstalledApp, operation appOperation: AppOperation, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let restoreContext = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        let appContext = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        
        let installBackupAppProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installBackupAppOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            app.managedObjectContext?.perform {
                guard let self = self else { return }
                
                let progress = self._installBackupApp(for: app, operation: appOperation, group: group, context: restoreContext) { (result) in
                    switch result
                    {
                    case .success(let installedApp): restoreContext.installedApp = installedApp
                    case .failure(let error):
                        restoreContext.error = error
                        appContext.error = error
                    }
                    
                    operation.finish()
                }
                installBackupAppProgress.addChild(progress, withPendingUnitCount: 100)
            }
        }
        progress.addChild(installBackupAppProgress, withPendingUnitCount: 30)
        
        let backupAppOperation = BackupAppOperation(action: .backup, context: restoreContext)
        backupAppOperation.resultHandler = { (result) in
            switch result
            {
            case .success: break
            case .failure(let error):
                restoreContext.error = error
                appContext.error = error
            }
        }
        backupAppOperation.addDependency(installBackupAppOperation)
        progress.addChild(backupAppOperation.progress, withPendingUnitCount: 15)
        
        let installAppProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installAppOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            app.managedObjectContext?.perform {
                guard let self = self else { return }
                
                let progress = self._install(app, operation: appOperation, group: group, context: appContext) { (result) in
                    completionHandler(result)
                    operation.finish()
                }
                installAppProgress.addChild(progress, withPendingUnitCount: 100)
            }
        }
        installAppOperation.addDependency(backupAppOperation)
        progress.addChild(installAppProgress, withPendingUnitCount: 55)
        
        group.add([installBackupAppOperation, backupAppOperation, installAppOperation])
        self.run([installBackupAppOperation, installAppOperation, backupAppOperation], context: group.context)
        
        return progress
    }
    
    private func _installBackupApp(for app: InstalledApp, operation appOperation: AppOperation, group: RefreshGroup, context: InstallAppOperationContext, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        guard let application = ALTApplication(fileURL: app.fileURL) else {
            completionHandler(.failure(OperationError.appNotFound))
            return progress
        }
        
        let prepareProgress = Progress.discreteProgress(totalUnitCount: 1)
        let prepareOperation = RSTAsyncBlockOperation { (operation) in
            app.managedObjectContext?.perform {
                do
                {
                    let temporaryDirectoryURL = context.temporaryDirectory.appendingPathComponent("AltBackup-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                    
                    guard let altbackupFileURL = Bundle.main.url(forResource: "AltBackup", withExtension: "ipa") else { throw OperationError.appNotFound }
                    
                    let unzippedAppBundleURL = try FileManager.default.unzipAppBundle(at: altbackupFileURL, toDirectory: temporaryDirectoryURL)
                    guard let unzippedAppBundle = Bundle(url: unzippedAppBundleURL) else { throw OperationError.invalidApp }
                    
                    if var infoDictionary = unzippedAppBundle.infoDictionary
                    {
                        // Replace name + bundle identifier so AltStore treats it as the same app.
                        infoDictionary["CFBundleDisplayName"] = app.name
                        infoDictionary[kCFBundleIdentifierKey as String] = app.bundleIdentifier
                        
                        // Add app-specific exported UTI so we can check later if this temporary backup app is still installed or not.
                        let installedAppUTI = ["UTTypeConformsTo": [],
                                               "UTTypeDescription": "AltStore Backup App",
                                               "UTTypeIconFiles": [],
                                               "UTTypeIdentifier": app.installedBackupAppUTI,
                                               "UTTypeTagSpecification": [:]] as [String : Any]
                        
                        var exportedUTIs = infoDictionary[Bundle.Info.exportedUTIs] as? [[String: Any]] ?? []
                        exportedUTIs.append(installedAppUTI)
                        infoDictionary[Bundle.Info.exportedUTIs] = exportedUTIs
                        
                        if let cachedApp = ALTApplication(fileURL: app.fileURL), let icon = cachedApp.icon?.resizing(to: CGSize(width: 180, height: 180))
                        {
                            let iconFileURL = unzippedAppBundleURL.appendingPathComponent("AppIcon.png")
                            
                            if let iconData = icon.pngData()
                            {
                                do
                                {
                                    try iconData.write(to: iconFileURL, options: .atomic)
                                    
                                    let bundleIcons = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": [iconFileURL.lastPathComponent]]]
                                    infoDictionary["CFBundleIcons"] = bundleIcons
                                }
                                catch
                                {
                                    print("Failed to write app icon data.", error)
                                }
                            }
                        }
                        
                        try (infoDictionary as NSDictionary).write(to: unzippedAppBundle.infoPlistURL)
                    }
                    
                    guard let backupApp = ALTApplication(fileURL: unzippedAppBundleURL) else { throw OperationError.invalidApp }
                    context.app = backupApp
                    
                    prepareProgress.completedUnitCount += 1
                }
                catch
                {
                    print(error)
                }
                
                operation.finish()
            }
        }
        progress.addChild(prepareProgress, withPendingUnitCount: 20)
        
        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        let installOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            guard let self = self else { return }
            
            guard let backupApp = context.app else {
                context.error = OperationError.invalidApp
                operation.finish()
                return
            }
            
            var appGroups = application.entitlements[.appGroups] as? [String] ?? []
            appGroups.append(Bundle.baseAltStoreAppGroupID)
            
            let additionalEntitlements: [ALTEntitlement: Any] = [.appGroups: appGroups]
            let progress = self._install(backupApp, operation: appOperation, group: group, context: context, additionalEntitlements: additionalEntitlements, cacheApp: false) { (result) in
                completionHandler(result)
                operation.finish()
            }
            installProgress.addChild(progress, withPendingUnitCount: 100)
        }
        installOperation.addDependency(prepareOperation)
        progress.addChild(installProgress, withPendingUnitCount: 80)
        
        group.add([prepareOperation, installOperation])
        self.run([prepareOperation, installOperation], context: group.context)
        
        return progress
    }
    
    func finish(_ operation: AppOperation, result: Result<InstalledApp, Error>, group: RefreshGroup, progress: Progress?)
    {
        let result = result.mapError { (resultError) -> Error in
            guard let error = resultError as? ALTServerError else { return resultError }
            
            switch error.code
            {
            case .deviceNotFound, .lostConnection:
                if let server = group.context.server, server.isPreferred || server.connectionType != .wireless
                {
                    // Preferred server (or not random wireless connection), so report errors normally.
                    return error
                }
                else
                {
                    // Not preferred server, so ignore these specific errors and throw serverNotFound instead.
                    return ConnectionError.serverNotFound
                }
                
            default: return error
            }
        }
        
        // Must remove before saving installedApp.
        if let currentProgress = self.progress(for: operation), currentProgress == progress
        {
            // Only remove progress if it hasn't been replaced by another one.
            self.set(nil, for: operation)
        }
        
        do
        {
            let installedApp = try result.get()
            group.set(.success(installedApp), forAppWithBundleIdentifier: installedApp.bundleIdentifier)
            
            if installedApp.bundleIdentifier == StoreApp.altstoreAppID
            {
                self.scheduleExpirationWarningLocalNotification(for: installedApp)
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
            
            if #available(iOS 14, *)
            {                
                WidgetCenter.shared.getCurrentConfigurations { (result) in
                    guard case .success(let widgets) = result else { return }
                    
                    guard let widget = widgets.first(where: { $0.configuration is ViewAppIntent }) else { return }
                    WidgetCenter.shared.reloadTimelines(ofKind: widget.kind)
                }
            }
            
            do { try installedApp.managedObjectContext?.save() }
            catch { print("Error saving installed app.", error) }
        }
        catch
        {
            group.set(.failure(error), forAppWithBundleIdentifier: operation.bundleIdentifier)
        }
    }
    
    func scheduleExpirationWarningLocalNotification(for app: InstalledApp)
    {
        let notificationDate = app.expirationDate.addingTimeInterval(-1 * 60 * 60 * 24) // 24 hours before expiration.
        
        let timeIntervalUntilNotification = notificationDate.timeIntervalSinceNow
        guard timeIntervalUntilNotification > 0 else {
            // Crashes if we pass negative value to UNTimeIntervalNotificationTrigger initializer.
            return
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeIntervalUntilNotification, repeats: false)
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("AltStore Expiring Soon", comment: "")
        content.body = NSLocalizedString("AltStore will expire in 24 hours. Open the app and refresh it to prevent it from expiring.", comment: "")
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: AppManager.expirationWarningNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    func run(_ operations: [Foundation.Operation], context: OperationContext?, requiresSerialQueue: Bool = false)
    {
        for operation in operations
        {
            switch operation
            {
            case _ where requiresSerialQueue: fallthrough
            case is InstallAppOperation, is RefreshAppOperation, is BackupAppOperation: self.serialOperationQueue.addOperation(operation)
            default: self.operationQueue.addOperation(operation)
            }
            
            context?.operations.add(operation)
        }
    }
    
    func progress(for operation: AppOperation) -> Progress?
    {
        switch operation
        {
        case .install, .update: return self.installationProgress[operation.bundleIdentifier]
        case .refresh, .activate, .deactivate, .backup, .restore: return self.refreshProgress[operation.bundleIdentifier]
        }
    }
    
    func set(_ progress: Progress?, for operation: AppOperation)
    {
        switch operation
        {
        case .install, .update: self.installationProgress[operation.bundleIdentifier] = progress
        case .refresh, .activate, .deactivate, .backup, .restore: self.refreshProgress[operation.bundleIdentifier] = progress
        }
    }
}
