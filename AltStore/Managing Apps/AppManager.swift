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
import UniformTypeIdentifiers

import AltStoreCore
import AltSign
import Roxas

extension AppManager
{
    static let didFetchSourceNotification = Notification.Name("io.altstore.AppManager.didFetchSource")
    static let didUpdatePatronsNotification = Notification.Name("io.altstore.AppManager.didUpdatePatrons")
    static let didAddSourceNotification = Notification.Name("io.altstore.AppManager.didAddSource")
    static let didRemoveSourceNotification = Notification.Name("io.altstore.AppManager.didRemoveSource")
    static let willInstallAppFromNewSourceNotification = Notification.Name("io.altstore.AppManager.willInstallAppFromNewSource")
    
    static let expirationWarningNotificationID = "altstore-expiration-warning"
    static let enableJITResultNotificationID = "altstore-enable-jit"
}

class AppManager: ObservableObject
{
    static let shared = AppManager()
    
    private(set) var updatePatronsResult: Result<Void, Error>?
    
    @Published
    private(set) var updateSourcesResult: Result<Void, Error>? // nil == loading
    
    private let operationQueue = OperationQueue()
    private let serialOperationQueue = OperationQueue()
    
    @Published private var installationProgress = [String: Progress]()
    @Published private var refreshProgress = [String: Progress]()
    private var cancellables: Set<AnyCancellable> = []
    
    private lazy var progressLock: UnsafeMutablePointer<os_unfair_lock> = {
        // Can't safely pass &os_unfair_lock to os_unfair_lock functions in Swift,
        // so pass UnsafeMutablePointer instead which is guaranteed to be safe.
        // https://stackoverflow.com/a/68615042
        let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: .init())
        return lock
    }()
    
    private init()
    {
        self.operationQueue.name = "com.altstore.AppManager.operationQueue"
        
        self.serialOperationQueue.name = "com.altstore.AppManager.serialOperationQueue"
        self.serialOperationQueue.maxConcurrentOperationCount = 1
        
        self.prepareSubscriptions()
    }
    
    deinit
    {
        // Should never be called, but do bookkeeping anyway.
        self.progressLock.deinitialize(count: 1)
        self.progressLock.deallocate()
    }
    
    func prepareSubscriptions()
    {
        /// Every time refreshProgress is changed, update all InstalledApps in memory
        /// so that app.isRefreshing == refreshProgress.keys.contains(app.bundleID)
        
        self.$refreshProgress
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
        #if MARKETPLACE
        
        if #available(iOS 17.4, *)
        {
            Task<Void, Never>(priority: .medium) {
                await AppMarketplace.shared.update()
            }
        }
        
        #else
        
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
                        
                        if var patchedApps = UserDefaults.standard.patchedApps, let index = patchedApps.firstIndex(of: app.bundleIdentifier)
                        {
                            patchedApps.remove(at: index)
                            UserDefaults.standard.patchedApps = patchedApps
                        }
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
        
        #endif
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
    
    func deactivateApps(for app: ALTApplication, presentingViewController: UIViewController, completion: @escaping (Result<Void, Error>) -> Void)
    {
        guard let activeAppsLimit = UserDefaults.standard.activeAppsLimit else { return completion(.success(())) }
        
        DispatchQueue.main.async {
            let activeApps = InstalledApp.fetchActiveApps(in: DatabaseManager.shared.viewContext)
                .filter { $0.bundleIdentifier != app.bundleIdentifier } // Don't count app towards total if it matches activating app
                .sorted { ($0.name, $0.refreshedDate) < ($1.name, $1.refreshedDate) }
            
            var title: String = NSLocalizedString("Cannot Activate More than 3 Apps", comment: "")
            let message: String
            
            if UserDefaults.standard.activeAppLimitIncludesExtensions
            {
                if app.appExtensions.isEmpty
                {
                    message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions. Please choose an app to deactivate.", comment: "")
                }
                else
                {
                    title = NSLocalizedString("Cannot Activate More than 3 Apps and App Extensions", comment: "")
                    
                    let appExtensionText = app.appExtensions.count == 1 ? NSLocalizedString("app extension", comment: "") : NSLocalizedString("app extensions", comment: "")
                    message = String(format: NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions, and “%@” contains %@ %@. Please choose an app to deactivate.", comment: ""), app.name, NSNumber(value: app.appExtensions.count), appExtensionText)
                }
            }
            else
            {
                message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps. Please choose an app to deactivate.", comment: "")
            }
            
            let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
            let availableActiveApps = max(activeAppsLimit - activeAppsCount, 0)
            let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? (1 + app.appExtensions.count) : 1
            guard requiredActiveSlots > availableActiveApps else { return completion(.success(())) }
            
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { (action) in
                completion(.failure(OperationError.cancelled))
            })
            
            for activeApp in activeApps where activeApp.bundleIdentifier != StoreApp.altstoreAppID
            {
                alertController.addAction(UIAlertAction(title: activeApp.name, style: .default) { (action) in
                    activeApp.isActive = false
                                    
                    self.deactivate(activeApp, presentingViewController: presentingViewController) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            activeApp.managedObjectContext?.perform {
                                activeApp.isActive = true
                                completion(.failure(error))
                            }
                            
                        case .success:
                            self.deactivateApps(for: app, presentingViewController: presentingViewController, completion: completion)
                        }
                    }
                })
            }
            
            presentingViewController.present(alertController, animated: true, completion: nil)
        }
    }
    
    func clearAppCache(completion: @escaping (Result<Void, Error>) -> Void)
    {
        let clearAppCacheOperation = ClearAppCacheOperation()
        clearAppCacheOperation.resultHandler = { result in
            completion(result)
        }
        
        self.run([clearAppCacheOperation], context: nil)
    }
}

extension AppManager
{
    func fetchSource(sourceURL: URL, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()) async throws -> Source
    {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchSource(sourceURL: sourceURL, managedObjectContext: managedObjectContext) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func fetchSources() async throws -> (Set<Source>, NSManagedObjectContext)
    {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchSources { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func add(@AsyncManaged _ source: Source, message: String? = NSLocalizedString("Make sure to only add sources that you trust.", comment: ""), presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceURL) = await $source.perform { ($0.name, $0.sourceURL) }
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        async let fetchedSource = try await self.fetchSource(sourceURL: sourceURL, managedObjectContext: context) // Fetch source async while showing alert.

        let title = String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName)
        let action = await UIAlertAction(title: NSLocalizedString("Add Source", comment: ""), style: .default)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message ?? "", primaryAction: action)

        // Wait for fetch to finish before saving context to make
        // sure there isn't already a source with this identifier.
        let sourceExists = try await fetchedSource.isAdded
        
        // This is just a sanity check, so pass nil for existingSource to keep code simple.
        guard !sourceExists else { throw SourceError.duplicate(source, existingSource: nil) }
        
        try await context.performAsync {
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didAddSourceNotification, object: source)
    }
    
    func remove(@AsyncManaged _ source: Source, presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceID) = await $source.perform { ($0.name, $0.identifier) }
        guard sourceID != Source.altStoreIdentifier else {
            throw OperationError.forbidden(failureReason: NSLocalizedString("The default AltStore source cannot be removed.", comment: ""))
        }
        
        let title = String(format: NSLocalizedString("Are you sure you want to remove the source “%@”?", comment: ""), sourceName)
        let message = NSLocalizedString("Any apps you've installed from this source will remain, but they'll no longer receive any app updates.", comment: "")
        let action = await UIAlertAction(title: NSLocalizedString("Remove Source", comment: ""), style: .destructive)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.performAsync {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID)
            guard let source = Source.first(satisfying: predicate, in: context) else { return } // Doesn't exist == success.
            
            context.delete(source)
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didRemoveSourceNotification, object: source)
    }
    
    @discardableResult
    func installAsync(@AsyncManaged _ app: StoreApp, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext()) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        @AsyncManaged var storeApp: StoreApp = app
        var didAddSource = false
        
        do
        {
            // Check if we need to add source first before installing app.
            if let source = await $app.perform({ $0.source }), try await !source.isAdded
            {
                // This app's source is not yet added, so add it first.
                guard let presentingViewController else { throw OperationError.sourceNotAdded(source) }
                
                let (appName, appBundleID, sourceID) = await $app.perform { ($0.name, $0.bundleIdentifier, source.identifier) }
                
                do
                {
                    let message = String(format: NSLocalizedString("You must add this source before installing apps from it.\n\n“%@” will begin downloading once it has been added.", comment: ""), appName)
                    try await AppManager.shared.add(source, message: message, presentingViewController: presentingViewController)
                }
                catch let error as CancellationError 
                {
                    throw error
                }
                catch
                {
                    // This should be an alert, so show directly rather than re-throwing error.
                    await presentingViewController.presentAlert(title: NSLocalizedString("Unable to Add Source", comment: ""), message: error.localizedDescription)
                    
                    // Don't rethrow error
                    // throw error
                    
                    throw CancellationError()
                }
                
                // Fetch persisted StoreApp to use for remainder of operation.
                storeApp = try await DatabaseManager.shared.viewContext.performAsync {
                    let fetchRequest = StoreApp.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                                         #keyPath(StoreApp.bundleIdentifier), appBundleID,
                                                         #keyPath(StoreApp.sourceIdentifier), sourceID)
                    
                    guard let storeApp = try DatabaseManager.shared.viewContext.fetch(fetchRequest).first else { throw OperationError.appNotFound(name: appName) }
                    return storeApp
                }
                
                didAddSource = true
            }
        }
        catch
        {
            let task = Task<AsyncManaged<InstalledApp>, Error> {
                throw error
            }
            task.cancel()
            
            let progress = Progress.discreteProgress(totalUnitCount: 1)
            progress.cancel()
            
            return (task, progress)
        }
        
        defer {
            if didAddSource
            {
                // Post notification from main queue _after_ assigning progress for it
                DispatchQueue.main.async { [storeApp] in
                    NotificationCenter.default.post(name: AppManager.willInstallAppFromNewSourceNotification, object: storeApp)
                }
            }
        }
        
        #if MARKETPLACE
        
        guard #available(iOS 17.4, *) else { fatalError("MARKETPLACE builds don't support iOS versions prior to 17.4") }
        
        let (task, progress) = await AppMarketplace.shared.install(storeApp, presentingViewController: presentingViewController, beginInstallationHandler: nil)
        return (task, progress)
        
        #else
        
        let group = await $storeApp.perform {
            self.installNonMarketplaceApp($0, presentingViewController: presentingViewController, context: context) { _ in }
        }
        
        let task = Task {
            try await withCheckedThrowingContinuation { continuation in
                group.completionHandler = { results in
                    do
                    {
                        guard let result = results.values.first else { throw OperationError.unknown() }
                        continuation.resume(with: result.map { AsyncManaged(wrappedValue: $0) })
                    }
                    catch
                    {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        return (task, group.progress)
        
        #endif
    }
    
    func updateAsync(@AsyncManaged _ installedApp: InstalledApp, to version: AppVersion? = nil, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext()) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        #if MARKETPLACE
        
        guard #available(iOS 17.4, *) else { fatalError("MARKETPLACE builds don't support iOS versions prior to 17.4") }

        let task = await AppMarketplace.shared.update(installedApp, to: version, presentingViewController: presentingViewController, beginInstallationHandler: nil)
        return task

        #else
        
        let group = await $installedApp.perform {
            self.updateNonMarketplaceApp($0, to: version, presentingViewController: presentingViewController, context: context) { _ in }
        }
        
        let task = Task {
            try await withCheckedThrowingContinuation { continuation in
                group.completionHandler = { results in
                    do
                    {
                        guard let result = results.values.first else { throw OperationError.unknown() }
                        continuation.resume(with: result.map { AsyncManaged(wrappedValue: $0) })
                    }
                    catch
                    {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        
        return (task, group.progress)

        #endif
    }
}

extension AppManager
{
    @available(*, renamed: "fetchSource(sourceURL:managedObjectContext:)")
    @discardableResult
    func fetchSource(sourceURL: URL,
                     managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext(),
                     dependencies: [Foundation.Operation] = [],
                     completionHandler: @escaping (Result<Source, Error>) -> Void) -> FetchSourceOperation
    {
        let fetchSourceOperation = FetchSourceOperation(sourceURL: sourceURL, managedObjectContext: managedObjectContext)
        fetchSourceOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success(let source):
                completionHandler(.success(source))
            }
        }
        
        for dependency in dependencies
        {
            fetchSourceOperation.addDependency(dependency)
        }
        
        self.run([fetchSourceOperation], context: nil)
        
        return fetchSourceOperation
    }
    
    @available(*, renamed: "fetchSources")
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
                
                let fetchSourceOperation = FetchSourceOperation(source: source, managedObjectContext: managedObjectContext)
                fetchSourceOperation.resultHandler = { (result) in
                    switch result
                    {
                    case .success(let source): fetchedSources.insert(source)
                    case .failure(let nsError as NSError):
                        let source = managedObjectContext.object(with: source.objectID) as! Source
                        let title = String(format: NSLocalizedString("Unable to Refresh “%@” Source", comment: ""), source.name)
                        
                        let error = nsError.withLocalizedTitle(title)
                        errors[source] = error
                        source.error = error.sanitizedForSerialization()
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
                    
                    NotificationCenter.default.post(name: AppManager.didFetchSourceNotification, object: self)
                }
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
    func updateKnownSources(completionHandler: @escaping (Result<([KnownSource], [KnownSource]), Error>) -> Void) -> UpdateKnownSourcesOperation
    {
        let updateKnownSourcesOperation = UpdateKnownSourcesOperation()
        updateKnownSourcesOperation.resultHandler = completionHandler
        self.run([updateKnownSourcesOperation], context: nil)
        
        return updateKnownSourcesOperation
    }
    
    func updatePatronsIfNeeded()
    {
        guard self.operationQueue.operations.allSatisfy({ !($0 is UpdatePatronsOperation) }) else {
            // There's already an UpdatePatronsOperation running.
            return
        }
        
        self.updatePatronsResult = nil
        
        let updatePatronsOperation = UpdatePatronsOperation()
        updatePatronsOperation.resultHandler = { (result) in
            do
            {
                try result.get()
                self.updatePatronsResult = .success(())
            }
            catch
            {
                print("Error updating Friend Zone Patrons:", error)
                self.updatePatronsResult = .failure(error)
            }
            
            NotificationCenter.default.post(name: AppManager.didUpdatePatronsNotification, object: self)
        }
        
        self.run([updatePatronsOperation], context: nil)
    }
    
    func updateAllSources(completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.updateSourcesResult = nil
        
        self.fetchSources() { (result) in
            do
            {
                do
                {
                    let (_, context) = try result.get()
                    try context.save()
                    
                    DispatchQueue.main.async {
                        self.updateSourcesResult = .success(())
                        completion(.success(()))
                    }
                }
                catch let error as AppManager.FetchSourcesError
                {
                    try error.managedObjectContext?.save()
                    throw error
                }
                catch let mergeError as MergeError
                {
                    guard let sourceID = mergeError.sourceID else { throw mergeError }
                    
                    let sanitizedError = (mergeError as NSError).sanitizedForSerialization()
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                        do
                        {
                            guard let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID), in: context) else { return }
                            
                            source.error = sanitizedError
                            try context.save()
                        }
                        catch
                        {
                            Logger.main.error("Failed to assign error \(sanitizedError.localizedErrorCode) to source \(sourceID, privacy: .public). \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    
                    throw mergeError
                }
            }
            catch var error as NSError
            {
                if error.localizedTitle == nil
                {
                    error = error.withLocalizedTitle(NSLocalizedString("Unable to Refresh Store", comment: ""))
                }
                
                DispatchQueue.main.async {
                    self.updateSourcesResult = .failure(error)
                    completion(.failure(error))
                }
            }
        }
    }
}

extension AppManager
{
    // Should never be called anymore, but there are some use cases left for classic AltStore.
    // So rather than making it private (like update()), we rename it to be clear it's not for marketplace apps.
    @discardableResult
    func installNonMarketplaceApp<T: AppProtocol>(_ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw context.error ?? OperationError.unknown() }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.install(app)
        self.perform([operation], presentingViewController: presentingViewController, group: group)
        
        return group
    }
    
    @discardableResult
    private func updateNonMarketplaceApp(_ installedApp: InstalledApp, to version: AppVersion? = nil, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        guard let appVersion = version ?? installedApp.storeApp?.latestSupportedVersion else {
            completionHandler(.failure(OperationError.appNotFound(name: installedApp.name)))
            
            let group = RefreshGroup(context: context)
            return group
        }
        
        let group = RefreshGroup(context: context)
        group.completionHandler = { (results) in
            do
            {
                guard let result = results.values.first else { throw OperationError.unknown() }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.update(appVersion)
        assert(operation.app as AnyObject !== installedApp) // Make sure we never accidentally "update" to already installed app.
        
        self.perform([operation], presentingViewController: presentingViewController, group: group)
        
        return group
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
                guard let result = results.values.first else { throw OperationError.unknown() }
                
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
                    guard let result = results.values.first else { throw OperationError.unknown() }

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
                guard let result = results.values.first else { throw OperationError.unknown() }
                
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
                guard let result = results.values.first else { throw OperationError.unknown() }
                
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
    
    func enableJIT(for installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        class Context: OperationContext, EnableJITContext
        {
            var installedApp: InstalledApp?
        }
        
        let appName = installedApp.name
        
        let context = Context()
        context.installedApp = installedApp
        
        let findServerOperation = self.findServer(context: context) { _ in }
        
        let enableJITOperation = EnableJITOperation(context: context)
        enableJITOperation.resultHandler = { (result) in
            switch result
            {
            case .success: completionHandler(.success(()))
            case .failure(let nsError as NSError):
                let localizedTitle = String(format: NSLocalizedString("Failed to Enable JIT for %@", comment: ""), appName)
                let error = nsError.withLocalizedTitle(localizedTitle)
                
                self.log(error, operation: .enableJIT, app: installedApp)
                completionHandler(.failure(error))
            }
        }
        enableJITOperation.addDependency(findServerOperation)
        
        self.run([enableJITOperation], context: context, requiresSerialQueue: true)
    }
    
    func patch(resignedApp: ALTApplication, presentingViewController: UIViewController, context authContext: AuthenticatedOperationContext, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> PatchAppOperation
    {
        class Context: InstallAppOperationContext, PatchAppContext
        {
        }
        
        guard let originalBundleID = resignedApp.bundle.infoDictionary?[Bundle.Info.altBundleID] as? String else {
            let context = Context(bundleIdentifier: resignedApp.bundleIdentifier, authenticatedContext: authContext)
            completionHandler(.failure(OperationError.invalidApp))
            
            return PatchAppOperation(context: context)
        }
        
        let context = Context(bundleIdentifier: originalBundleID, authenticatedContext: authContext)
        context.resignedApp = resignedApp
        
        let patchAppOperation = PatchAppOperation(context: context)
        let sendAppOperation = SendAppOperation(context: context)
        let installOperation = InstallAppOperation(context: context)
        
        let installationProgress = Progress.discreteProgress(totalUnitCount: 100)
        installationProgress.addChild(sendAppOperation.progress, withPendingUnitCount: 40)
        installationProgress.addChild(installOperation.progress, withPendingUnitCount: 60)
        
        /* Patch */
        patchAppOperation.resultHandler = { [weak patchAppOperation] (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success:
                // Kinda hacky that we're calling patchAppOperation's progressHandler manually, but YOLO.
                patchAppOperation?.progressHandler?(installationProgress, NSLocalizedString("Patching placeholder app...", comment: ""))
            }
        }
        
        /* Send */
        sendAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let installationConnection): context.installationConnection = installationConnection
            }
        }
        sendAppOperation.addDependency(patchAppOperation)

        
        /* Install */
        installOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let installedApp): completionHandler(.success(installedApp))
            }
        }
        installOperation.addDependency(sendAppOperation)
        
        self.run([patchAppOperation, sendAppOperation, installOperation], context: context.authenticatedContext)
        return patchAppOperation
    }
    
    func installationProgress(for app: AppProtocol) -> Progress?
    {
        os_unfair_lock_lock(self.progressLock)
        defer { os_unfair_lock_unlock(self.progressLock) }
        
        let progress = self.installationProgress[app.bundleIdentifier]
        return progress
    }
    
    func refreshProgress(for app: AppProtocol) -> Progress?
    {
        os_unfair_lock_lock(self.progressLock)
        defer { os_unfair_lock_unlock(self.progressLock) }
        
        let progress = self.refreshProgress[app.bundleIdentifier]
        return progress
    }
    
    func isActivelyManagingApp(withBundleID bundleID: String) -> Bool
    {
        let isActivelyManaging = self.installationProgress.keys.contains(bundleID) || self.refreshProgress.keys.contains(bundleID)
        return isActivelyManaging
    }
}

extension AppManager
{
    @discardableResult
    func backgroundRefresh(_ installedApps: [InstalledApp], presentsNotifications: Bool = true, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void) -> BackgroundRefreshAppsOperation
    {
        let backgroundRefreshAppsOperation = BackgroundRefreshAppsOperation(installedApps: installedApps)
        backgroundRefreshAppsOperation.resultHandler = completionHandler
        backgroundRefreshAppsOperation.presentsFinishedNotification = presentsNotifications
        self.run([backgroundRefreshAppsOperation], context: nil)
        
        return backgroundRefreshAppsOperation
    }
}

internal extension AppManager
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
        
        var loggedErrorOperation: LoggedError.Operation {
            switch self
            {
            case .install: return .install
            case .update: return .update
            case .refresh: return .refresh
            case .activate: return .activate
            case .deactivate: return .deactivate
            case .backup: return .backup
            case .restore: return .restore
            }
        }
    }
}

private extension AppManager
{
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
                case .install(let app):
                    let installProgress = self._install(app, operation: operation, group: group, reviewPermissions: .all) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(installProgress, withPendingUnitCount: 80)
                    
                case .update(let app):
                    let updateProgress = self._install(app, operation: operation, group: group, reviewPermissions: .added) { (result) in
                        self.finish(operation, result: result, group: group, progress: progress)
                    }
                    progress?.addChild(updateProgress, withPendingUnitCount: 80)
                    
                case .activate(let app) where UserDefaults.standard.isLegacyDeactivationSupported: fallthrough
                case .refresh(let app):
                    // Check if backup app is installed in place of real app.
                    let uti = UTType(app.installedBackupAppUTI)

                    if app.certificateSerialNumber != group.context.certificate?.serialNumber ||
                        uti != nil ||
                        app.needsResign ||
                        (group.context.server?.connectionType == .local && !UserDefaults.standard.localServerSupportsRefreshing)
                    {
                        // Resign app instead of just refreshing profiles because either:
                        // * Refreshing using different certificate
                        // * Backup app is still installed
                        // * App explicitly needs resigning
                        // * Device is jailbroken and using AltDaemon on iOS 14.0 or later (b/c refreshing with provisioning profiles is broken)
                        
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
    
    private func _install(_ app: AppProtocol,
                          operation appOperation: AppOperation,
                          group: RefreshGroup,
                          context: InstallAppOperationContext? = nil,
                          reviewPermissions permissionReviewMode: VerifyAppOperation.PermissionReviewMode = .none,
                          additionalEntitlements: [ALTEntitlement: Any]? = nil,
                          cacheApp: Bool = true,
                          completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let context = context ?? InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        assert(context.authenticatedContext === group.context)
        
        context.beginInstallationHandler = { (installedApp) in
            switch appOperation
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
        
        var verifyPledgeOperation: VerifyAppPledgeOperation?
        if let storeApp = app.storeApp
        {
            verifyPledgeOperation = VerifyAppPledgeOperation(storeApp: storeApp, presentingViewController: context.presentingViewController)
            verifyPledgeOperation?.resultHandler = { result in
                switch result
                {
                case .failure(let error): context.error = error
                case .success: break
                }
            }
        }
        
        /* Download */
        let downloadedAppURL = context.temporaryDirectory.appendingPathComponent("Cached.app")
        let downloadOperation = DownloadAppOperation(app: downloadingApp, destinationURL: downloadedAppURL, context: context)
        downloadOperation.resultHandler = { (result) in
            do
            {
                let app = try result.get()
                context.app = app
            }
            catch
            {
                context.error = error
            }
        }
        progress.addChild(downloadOperation.progress, withPendingUnitCount: 25)
        
        if let verifyPledgeOperation
        {
            downloadOperation.addDependency(verifyPledgeOperation)
        }
        
        
        /* Verify App */
        let permissionsMode = UserDefaults.shared.permissionCheckingDisabled ? .none : permissionReviewMode
        let verifyOperation = VerifyAppOperation(permissionsMode: permissionsMode, context: context)
        verifyOperation.resultHandler = { (result) in
            do
            {
                try result.get()
                
                // Wait until we've finished verifying app before caching it.
                if let app = context.app, cacheApp
                {
                    try FileManager.default.copyItem(at: app.fileURL, to: InstalledApp.fileURL(for: app), shouldReplace: true)
                }
            }
            catch
            {
                context.error = error
            }
        }
        verifyOperation.addDependency(downloadOperation)
        
        
        /* Deactivate Apps (if necessary) */
        let deactivateAppsOperation = RSTAsyncBlockOperation { [weak self] (operation) in
            do
            {
                // Only attempt to deactivate apps if we're installing a new app.
                // We handle deactivating apps separately when activating an app.
                guard case .install = appOperation else {
                    operation.finish()
                    return
                }
                
                if let error = context.error
                {
                    throw error
                }
                                
                guard let app = context.app, let presentingViewController = context.authenticatedContext.presentingViewController else { throw OperationError.invalidParameters }
                
                self?.deactivateApps(for: app, presentingViewController: presentingViewController) { result in
                    switch result
                    {
                    case .failure(let error): group.context.error = error
                    case .success: break
                    }
                    
                    operation.finish()
                }
            }
            catch
            {
                group.context.error = error
                operation.finish()
            }
        }
        deactivateAppsOperation.addDependency(verifyOperation)
        
        
        /* Patch App */
        let patchAppOperation = RSTAsyncBlockOperation { operation in
            do
            {
                // Only attempt to patch app if we're installing a new app, not refreshing existing app.
                // Post reboot, we install the correct jailbreak app by refreshing the patched app,
                // so this check avoids infinite recursion.
                guard case .install = appOperation else {
                    operation.finish()
                    return
                }
                
                guard let presentingViewController = context.presentingViewController else { return operation.finish() }
                
                if let error = context.error
                {
                    throw error
                }
                
                guard let app = context.app else { throw OperationError.invalidParameters }
                
                guard let isUntetherRequired = app.bundle.infoDictionary?[Bundle.Info.untetherRequired] as? Bool,
                      let minimumiOSVersionString = app.bundle.infoDictionary?[Bundle.Info.untetherMinimumiOSVersion] as? String,
                      let maximumiOSVersionString = app.bundle.infoDictionary?[Bundle.Info.untetherMaximumiOSVersion] as? String,
                      case let minimumiOSVersion = OperatingSystemVersion(string: minimumiOSVersionString),
                      case let maximumiOSVersion = OperatingSystemVersion(string: maximumiOSVersionString)
                else { return operation.finish() }
                
                let iOSVersion = ProcessInfo.processInfo.operatingSystemVersion
                let iOSVersionSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumiOSVersion) &&
                (!ProcessInfo.processInfo.isOperatingSystemAtLeast(maximumiOSVersion) || maximumiOSVersion == iOSVersion)
                
                guard isUntetherRequired, iOSVersionSupported, UIDevice.current.supportsFugu14 else { return operation.finish() }
                
                guard let patchAppLink = app.bundle.infoDictionary?[Bundle.Info.untetherURL] as? String,
                      let patchAppURL = URL(string: patchAppLink)
                else { throw OperationError.invalidApp }
                
                let patchApp = AnyApp(name: app.name, bundleIdentifier: app.bundleIdentifier, url: patchAppURL, storeApp: nil)
                
                DispatchQueue.main.async {
                    let storyboard = UIStoryboard(name: "PatchApp", bundle: nil)
                    let navigationController = storyboard.instantiateInitialViewController() as! UINavigationController
                    
                    let patchViewController = navigationController.topViewController as! PatchViewController
                    patchViewController.patchApp = patchApp
                    patchViewController.completionHandler = { [weak presentingViewController] (result) in
                        switch result
                        {
                        case .failure(OperationError.cancelled): break // Ignore
                        case .failure(let error): group.context.error = error
                        case .success: group.context.error = OperationError.cancelled
                        }
                        
                        operation.finish()
                        
                        DispatchQueue.main.async {
                            presentingViewController?.dismiss(animated: true, completion: nil)
                        }
                    }
                    presentingViewController.present(navigationController, animated: true, completion: nil)                    
                }
            }
            catch
            {
                group.context.error = error
                operation.finish()
            }
        }
        patchAppOperation.addDependency(deactivateAppsOperation)
        
        
        /* Refresh Anisette Data */
        let refreshAnisetteDataOperation = FetchAnisetteDataOperation(context: group.context)
        refreshAnisetteDataOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let anisetteData): group.context.session?.anisetteData = anisetteData
            }
        }
        refreshAnisetteDataOperation.addDependency(patchAppOperation)
        
        
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
        
        var operations = [verifyPledgeOperation, downloadOperation, verifyOperation, deactivateAppsOperation, patchAppOperation, refreshAnisetteDataOperation, fetchProvisioningProfilesOperation, resignAppOperation, sendAppOperation, installOperation].compactMap { $0 }
        group.add(operations)
        
        if let storeApp = downloadingApp.storeApp, storeApp.isPledgeRequired
        {
            // Patreon apps may require authenticating with WebViewController,
            // so make sure to run DownloadAppOperation serially.
            self.run([downloadOperation], context: group.context, requiresSerialQueue: true)
            
            if let index = operations.firstIndex(of: downloadOperation)
            {
                // Remove downloadOperation from operations to prevent running it twice.
                operations.remove(at: index)
            }
        }

        self.run(operations, context: group.context)
        
        return progress
    }
    
    private func _refresh(_ app: InstalledApp, operation: AppOperation, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        let context = AppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        context.app = ALTApplication(fileURL: app.fileURL)
        
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
                
            case .failure(ALTServerError.unknownRequest), .failure(~OperationError.Code.appNotFound):
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
        
        if let error = context.error
        {
            completionHandler(.failure(error))
            return progress
        }
        
        guard let application = ALTApplication(fileURL: app.fileURL) else {
            completionHandler(.failure(OperationError.appNotFound(name: app.name)))
            return progress
        }
        
        let prepareProgress = Progress.discreteProgress(totalUnitCount: 1)
        let prepareOperation = RSTAsyncBlockOperation { (operation) in
            app.managedObjectContext?.perform {
                do
                {
                    let temporaryDirectoryURL = context.temporaryDirectory.appendingPathComponent("AltBackup-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                    
                    guard let altbackupFileURL = Bundle.main.url(forResource: "AltBackup", withExtension: "ipa") else { throw OperationError.appNotFound(name: "AltBackup") }
                    
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
                    
                    context.error = error
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
                    return OperationError(.serverNotFound)
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
            
            WidgetCenter.shared.reloadAllTimelines()
            
            do 
            {
                try installedApp.managedObjectContext?.save()
            }
            catch
            {
                Logger.main.error("Failed to save InstalledApp to database. \(error.localizedDescription, privacy: .public)")
                throw error
            }
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
            group.set(.failure(error), forAppWithBundleIdentifier: operation.bundleIdentifier)
            
            self.log(error, operation: operation.loggedErrorOperation, app: operation.app)
        }
    }
}

internal extension AppManager
{
    func run(_ operations: [Foundation.Operation], context: OperationContext?, requiresSerialQueue: Bool = false)
    {
        // Find "Install AltStore" operation if it already exists in `context`
        // so we can ensure it runs after any additional serial operations in `operations`.
        let installAltStoreOperation = context?.operations.allObjects.lazy.compactMap { $0 as? InstallAppOperation }.first { $0.context.bundleIdentifier == StoreApp.altstoreAppID }
        
        for operation in operations
        {
            switch operation
            {
            case _ where requiresSerialQueue: fallthrough
            case is InstallAppOperation, is RefreshAppOperation, is BackupAppOperation, is VerifyAppPledgeOperation:
                if let installAltStoreOperation = operation as? InstallAppOperation, installAltStoreOperation.context.bundleIdentifier == StoreApp.altstoreAppID
                {
                    // Add dependencies on previous serial operations in `context` to ensure re-installing AltStore goes last.
                    let previousSerialOperations = context?.operations.allObjects.filter { self.serialOperationQueue.operations.contains($0) }
                    previousSerialOperations?.forEach { installAltStoreOperation.addDependency($0) }
                }
                else if let installAltStoreOperation = installAltStoreOperation
                {
                    // Re-installing AltStore should _always_ be the last serial operation in `context`.
                    installAltStoreOperation.addDependency(operation)
                }
                
                self.serialOperationQueue.addOperation(operation)
                
            default: self.operationQueue.addOperation(operation)
            }
            
            context?.operations.add(operation)
        }
    }
    
    func progress(for operation: AppOperation) -> Progress?
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        
        os_unfair_lock_lock(self.progressLock)
        defer { os_unfair_lock_unlock(self.progressLock) }
        
        switch operation
        {
        case .install, .update: return self.installationProgress[bundleID]
        case .refresh, .activate, .deactivate, .backup, .restore: return self.refreshProgress[bundleID]
        }
    }
    
    func set(_ progress: Progress?, for operation: AppOperation)
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        
        os_unfair_lock_lock(self.progressLock)
        defer { os_unfair_lock_unlock(self.progressLock) }
        
        switch operation
        {
        case .install, .update: self.installationProgress[bundleID] = progress
        case .refresh, .activate, .deactivate, .backup, .restore: self.refreshProgress[bundleID] = progress
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
    
    func log(_ error: Error, operation: LoggedError.Operation, app: AppProtocol)
    {
        switch error
        {
        case is CancellationError: return // Don't log CancellationErrors
        case let nsError as NSError where nsError.domain == CancellationError()._domain: return
        default: break
        }
        
        // Sanitize NSError on same thread before performing background task.
        let sanitizedError = (error as NSError).sanitizedForSerialization()
        
        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            var app = app
            if let managedApp = app as? NSManagedObject, let tempApp = context.object(with: managedApp.objectID) as? AppProtocol
            {
                app = tempApp
            }
            
            do
            {
                _ = LoggedError(error: sanitizedError, app: app, operation: operation, context: context)
                try context.save()
            }
            catch let saveError
            {
                print("[ALTLog] Failed to log error \(sanitizedError.domain) code \(sanitizedError.code) for \(app.bundleIdentifier):", saveError)
            }
        }
    }
}
