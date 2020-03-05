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

import AltSign
import AltKit

import Roxas

extension AppManager
{
    static let didFetchSourceNotification = Notification.Name("com.altstore.AppManager.didFetchSource")
    
    static let expirationWarningNotificationID = "altstore-expiration-warning"
    
    static let whitelistedSideloadingBundleIDs: Set<String> = ["science.xnu.undecimus"]
}

class AppManager
{
    static let shared = AppManager()
    
    private let operationQueue = OperationQueue()
    private let serialOperationQueue = OperationQueue()
    private let processingQueue = DispatchQueue(label: "com.altstore.AppManager.processingQueue")
    
    private var installationProgress = [String: Progress]()
    private var refreshProgress = [String: Progress]()
    
    private init()
    {
        self.operationQueue.name = "com.altstore.AppManager.operationQueue"
        
        self.serialOperationQueue.name = "com.altstore.AppManager.serialOperationQueue"
        self.serialOperationQueue.maxConcurrentOperationCount = 1
    }
}

extension AppManager
{
    func update()
    {
        #if targetEnvironment(simulator)
        // Apps aren't ever actually installed to simulator, so just do nothing rather than delete them from database.
        return
        #else
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
        
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.returnsObjectsAsFaults = false
        
        do
        {
            let installedApps = try context.fetch(fetchRequest)
            
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
                let uti = UTTypeCopyDeclaration(app.installedAppUTI as CFString)?.takeRetainedValue() as NSDictionary?
                
                if app.bundleIdentifier == StoreApp.altstoreAppID
                {
                    self.scheduleExpirationWarningLocalNotification(for: app)
                }
                else
                {
                    if uti == nil && !legacySideloadedApps.contains(app.bundleIdentifier)
                    {
                        // This UTI is not declared by any apps, which means this app has been deleted by the user.
                        // This app is also not a legacy sideloaded app, so we can assume it's fine to delete it.
                        context.delete(app)
                    }
                }
            }
            
            try context.save()
        }
        catch
        {
            print("Error while fetching installed apps")
        }
        
        #endif
    }
    
//    func activateApps(completionHandler: @escaping (Result<[ALTProvisioningProfile: Error], Error>) -> Void)
//    {
//        let context = OperationContext()
//                
//        let findServerOperation = FindServerOperation()
//        findServerOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let server): context.server = server
//            }
//        }
//        
//        let activateAppsOperation = ActivateAppsOperation(context: context)
//        activateAppsOperation.resultHandler = { (result) in
//            completionHandler(result)
//        }
//        activateAppsOperation.addDependency(findServerOperation)
//        
//        self.run([findServerOperation, activateAppsOperation])
//    }
    
    @discardableResult
    func authenticate(presentingViewController: UIViewController?, context: AuthenticatedOperationContext? = nil, completionHandler: @escaping (Result<(ALTTeam, ALTCertificate, ALTAppleAPISession), Error>) -> Void) -> AuthenticatedOperationContext
    {
        let context = context ?? AuthenticatedOperationContext()
        
        let findServerOperation = FindServerOperation()
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let server): context.server = server
            }
        }
        
        let authenticationOperation = AuthenticationOperation(context: context, presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let team, let certificate, let session):
                context.session = session
                context.team = team
                context.certificate = certificate
            }
            
            completionHandler(result)
        }
        authenticationOperation.addDependency(findServerOperation)
        
        self.run([findServerOperation, authenticationOperation])
        
        return context
    }
    
    @discardableResult
    func rst_authenticate(presentingViewController: UIViewController?, context: AuthenticatedOperationContext? = nil, completionHandler: @escaping (Result<(ALTTeam, ALTCertificate, ALTAppleAPISession), Error>) -> Void) -> AuthenticationOperation
    {
        let context = context ?? AuthenticatedOperationContext()
        
        let findServerOperation = FindServerOperation()
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let server): context.server = server
            }
        }
        
        let authenticationOperation = AuthenticationOperation(context: context, presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success((let team, let certificate, let session)):
                context.session = session
                context.team = team
                context.certificate = certificate
            }
            
            completionHandler(result)
        }
        authenticationOperation.addDependency(findServerOperation)
        
        self.run([findServerOperation, authenticationOperation])
        
        return authenticationOperation
    }
}

extension AppManager
{
    func fetchSource(completionHandler: @escaping (Result<Source, Error>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            guard let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context) else {
                return completionHandler(.failure(OperationError.noSources))
            }
            
            let fetchSourceOperation = FetchSourceOperation(sourceURL: source.sourceURL)
            fetchSourceOperation.resultHandler = { (result) in
                switch result
                {
                case .failure(let error):
                    completionHandler(.failure(error))
                    
                case .success(let source):
                    completionHandler(.success(source))
                    NotificationCenter.default.post(name: AppManager.didFetchSourceNotification, object: self)
                }
            }
            self.run([fetchSourceOperation])
        }
    }
    
    func fetchAppIDs(completionHandler: @escaping (Result<([AppID], NSManagedObjectContext), Error>) -> Void)
    {
        var context: AuthenticatedOperationContext!
        context = self.authenticate(presentingViewController: nil) { (result) in
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success:
                let fetchAppIDsOperation = FetchAppIDsOperation(context: context)
                fetchAppIDsOperation.resultHandler = completionHandler
                self.run([fetchAppIDsOperation])
            }
        }
    }
    
    func deactivate(_ installedApp: InstalledApp, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        let context = OperationContext()
        
        let findServerOperation = FindServerOperation()
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let server): context.server = server
            }
        }
        
        let deactivateAppOperation = DeactivateAppOperation(app: installedApp, context: context)
        deactivateAppOperation.resultHandler = { (result) in
            completionHandler(result)
        }
        deactivateAppOperation.addDependency(findServerOperation)
        
        self.run([findServerOperation, deactivateAppOperation])
    }
}

extension AppManager
{
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
//    func install<T: AppProtocol>(_ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext? = nil,  completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
//    {
//        // Authenticate -> Download -> Fetch Provisioning Profile -> Resign App -> Send -> Install
//
//        if let progress = self.installationProgress(for: app)
//        {
//            return progress
//        }
//
//        let progress = Progress.discreteProgress(totalUnitCount: 100)
//        let bundleIdentifier = app.bundleIdentifier
//
//        let managedObjectContext: NSManagedObjectContext?
//        if let app = app as? NSManagedObject & AppProtocol, let context = app.managedObjectContext
//        {
//            managedObjectContext = context
//        }
//        else
//        {
//            managedObjectContext = nil
//        }
//
//        var operations = [Operation]()
//        var authenticatedContext: AuthenticatedOperationContext = context ?? AuthenticatedOperationContext()
//
//        func finish(_ result: Result<InstalledApp, Error>)
//        {
//            self.installationProgress[bundleIdentifier] = nil
//
//            do
//            {
//                let installedApp = try self.process(result, server: authenticatedContext.server)
//                installedApp.managedObjectContext?.performAndWait {
//                    do { try installedApp.managedObjectContext?.save() }
//                    catch { print("Error saving installed app.", error) }
//
//                    if let index = UserDefaults.standard.legacySideloadedApps?.firstIndex(of: installedApp.bundleIdentifier)
//                    {
//                        // No longer a legacy sideloaded app, so remove it from cached list.
//                        UserDefaults.standard.legacySideloadedApps?.remove(at: index)
//                    }
//
//                    completionHandler(.success(installedApp))
//                }
//            }
//            catch
//            {
//                completionHandler(.failure(error))
//            }
//        }
//
//        /* Authenticate */
//        authenticatedContext = self.authenticate(presentingViewController: presentingViewController, context: authenticatedContext) { (result) in
//            switch result
//            {
//            case .failure(let error):
//                finish(.failure(error))
//
//            case .success:
//                let context = InstallAppOperationContext(bundleIdentifier: bundleIdentifier, authenticatedContext: authenticatedContext)
//
//                /* Prepare Developer Account */
//                let prepareDeveloperAccountOperation = PrepareDeveloperAccountOperation(context: authenticatedContext)
//                prepareDeveloperAccountOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success: break
//                    }
//                }
//                operations.append(prepareDeveloperAccountOperation)
//
//
//                /* Download */
//                var downloadOperation: DownloadAppOperation!
//
//                if let managedObjectContext = managedObjectContext
//                {
//                    managedObjectContext.performAndWait {
//                        downloadOperation = DownloadAppOperation(app: app, context: context)
//                    }
//                }
//                else
//                {
//                    downloadOperation = DownloadAppOperation(app: app, context: context)
//                }
//
//                downloadOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let app): context.app = app
//                    }
//                }
//                progress.addChild(downloadOperation.progress, withPendingUnitCount: 25)
//                operations.append(downloadOperation)
//
//
//                /* Refresh Anisette Data */
//                let refreshAnisetteDataOperation = FetchAnisetteDataOperation(context: authenticatedContext)
//                refreshAnisetteDataOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let anisetteData): authenticatedContext.session?.anisetteData = anisetteData
//                    }
//                }
//                refreshAnisetteDataOperation.addDependency(downloadOperation)
//                operations.append(refreshAnisetteDataOperation)
//
//
//                /* Fetch Provisioning Profiles */
//                let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
//                fetchProvisioningProfilesOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
//                    }
//                }
//                fetchProvisioningProfilesOperation.addDependency(prepareDeveloperAccountOperation)
//                fetchProvisioningProfilesOperation.addDependency(refreshAnisetteDataOperation)
//                progress.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 5)
//                operations.append(fetchProvisioningProfilesOperation)
//
//
//                /* Resign */
//                let resignAppOperation = ResignAppOperation(context: context)
//                resignAppOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let resignedApp): context.resignedApp = resignedApp
//                    }
//                }
//                resignAppOperation.addDependency(fetchProvisioningProfilesOperation)
//                progress.addChild(resignAppOperation.progress, withPendingUnitCount: 20)
//                operations.append(resignAppOperation)
//
//
//                /* Send */
//                let sendAppOperation = SendAppOperation(context: context)
//                sendAppOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let installationConnection): context.installationConnection = installationConnection
//                    }
//                }
//                progress.addChild(sendAppOperation.progress, withPendingUnitCount: 20)
//                sendAppOperation.addDependency(resignAppOperation)
//                operations.append(sendAppOperation)
//
//
//                /* Install */
//                let installOperation = InstallAppOperation(context: context)
//                installOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): finish(.failure(error))
//                    case .success(let installedApp):
//                        if let app = app as? StoreApp, let storeApp = installedApp.managedObjectContext?.object(with: app.objectID) as? StoreApp
//                        {
//                            installedApp.storeApp = storeApp
//                        }
//
//                        finish(.success(installedApp))
//                    }
//                }
//                progress.addChild(installOperation.progress, withPendingUnitCount: 30)
//                installOperation.addDependency(sendAppOperation)
//                operations.append(installOperation)
//
//                self.run(operations)
//            }
//        }
//
//        self.installationProgress[app.bundleIdentifier] = progress
//        return progress
//    }
//
//    @discardableResult
//    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup? = nil) -> RefreshGroup
//    {
//        let apps = installedApps.filter { self.refreshProgress(for: $0) == nil || self.refreshProgress(for: $0)?.isCancelled == true }
//        let appBundleIDs = apps.map { $0.bundleIdentifier }
//
//        let group = group ?? RefreshGroup()
//
//        for app in apps
//        {
//            let progress = Progress.discreteProgress(totalUnitCount: 100)
//            group.set(progress, for: app)
//
//            // Make sure this is set before function returns so calling method can use it immediately.
//            self.refreshProgress[app.bundleIdentifier] = progress
//        }
//
//        var token: NSKeyValueObservation!
//        token = group.observe(\.isFinished) { (group, change) in
//            guard group.isFinished else { return }
//
//            for bundleID in appBundleIDs
//            {
//                if let progress = self.refreshProgress[bundleID], progress == group.progress(forAppWithBundleIdentifier: bundleID)
//                {
//                    // Only remove progress if it hasn't been replaced by another one.
//                    self.refreshProgress[bundleID] = nil
//                }
//            }
//
//            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
//                guard let altstore = InstalledApp.fetchAltStore(in: context) else { return }
//                self.scheduleExpirationWarningLocalNotification(for: altstore)
//            }
//
//            // Explicitly reference token in closure to ensure it is strongly captured.
//            token.invalidate()
//        }
//
//        return self._refresh(apps, presentingViewController: presentingViewController, group: group)
//    }
//
//    @discardableResult
//    private func _refresh(_ apps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup) -> RefreshGroup
//    {
//        func finish(_ result: Result<InstalledApp, Error>, context: AppOperationContext)
//        {
//            do
//            {
//                let installedApp = try self.process(result, server: group.context.server)
//                group.set(.success(installedApp), forAppWithBundleIdentifier: context.bundleIdentifier)
//
//                installedApp.managedObjectContext?.performAndWait {
//
//                    // Must remove before saving installedApp.
//                    if let progress = self.refreshProgress[installedApp.bundleIdentifier], progress == group.progress(forAppWithBundleIdentifier: installedApp.bundleIdentifier)
//                    {
//                        // Only remove progress if it hasn't been replaced by another one.
//                        self.refreshProgress[installedApp.bundleIdentifier] = nil
//                    }
//
//                    do { try installedApp.managedObjectContext?.save() }
//                    catch { print("Error saving installed app.", error) }
//                }
//            }
//            catch
//            {
//                group.set(.failure(error), forAppWithBundleIdentifier: context.bundleIdentifier)
//            }
//        }
//
//        func refresh()
//        {
//            /* Authenticate (if necessary) */
//            guard group.context.session != nil else {
//                self.authenticate(presentingViewController: presentingViewController, context: group.context) { (result) in
//                    switch result
//                    {
//                    case .failure: group.finish()
//                    case .success: self._refresh(apps, presentingViewController: presentingViewController, group: group)
//                    }
//                }
//
//                return
//            }
//
//            /* Prepare Developer Account (if necessary) */
//            guard group.didPrepareDeveloperAccount else {
//                let prepareDeveloperAccountOperation = PrepareDeveloperAccountOperation(context: group.context)
//                prepareDeveloperAccountOperation.resultHandler = { (result) in
//                    do
//                    {
//                        try self.process(result, server: group.context.server)
//                        group.didPrepareDeveloperAccount = true
//
//                        self._refresh(apps, presentingViewController: presentingViewController, group: group)
//                    }
//                    catch
//                    {
//                        group.context.error = error
//                        group.finish()
//                    }
//                }
//
//                self.run([prepareDeveloperAccountOperation])
//
//                return
//            }
//
//            var operations = [Foundation.Operation]()
//
//            for app in apps
//            {
//                let progress = self.refreshProgress[app.bundleIdentifier]
//                let managedObjectContext = app.managedObjectContext
//
//                let context = AppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
//                context.app = ALTApplication(fileURL: app.fileURL)
//
//                guard group.context.certificate?.serialNumber == app.certificateSerialNumber else {
//                    let installOperation = RSTAsyncBlockOperation { (operation) in
//                        print("Certificate revoked! Re-signing app:", context.bundleIdentifier)
//
//                        managedObjectContext?.perform {
//                            let installProgress = self.install(app, presentingViewController: presentingViewController, context: group.context) { (result) in
//                                finish(result, context: context)
//                                operation.finish()
//                            }
//
//                            progress?.addChild(installProgress, withPendingUnitCount: 100)
//                        }
//                    }
//
//                    operations.append(installOperation)
//                    continue
//                }
//
//                progress?.completedUnitCount += 30
//
//                /* Fetch Provisioning Profiles */
//                let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
//                fetchProvisioningProfilesOperation.resultHandler = { (result) in
//                    switch result
//                    {
//                    case .failure(let error): context.error = error
//                    case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
//                    }
//                }
//                progress?.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 40)
//                operations.append(fetchProvisioningProfilesOperation)
//
//
//                /* Refresh */
//                let refreshAppOperation = RefreshAppOperation(context: context)
//                refreshAppOperation.resultHandler = { (result) in
//                    finish(result, context: context)
//                }
//                progress?.addChild(refreshAppOperation.progress, withPendingUnitCount: 30)
//                refreshAppOperation.addDependency(fetchProvisioningProfilesOperation)
//                operations.append(refreshAppOperation)
//            }
//
//            group.runOperations(operations)
//        }
//
//        if let managedObjectContext = apps.first(where: { $0.managedObjectContext != nil})?.managedObjectContext
//        {
//            managedObjectContext.perform {
//                refresh()
//            }
//        }
//        else
//        {
//            refresh()
//        }
//
//        return group
//    }
    
//    @discardableResult
//    private func rst_install(_ apps: [AppProtocol], presentingViewController: UIViewController?, refreshGroup: RefreshGroup? = nil) -> RefreshGroup
//    {
//        let apps = apps.filter { self.installationProgress(for: $0) == nil || self.installationProgress(for: $0)?.isCancelled == true }
//    }
    
    enum AppOperation
    {
        case install(AppProtocol)
        case refresh(AppProtocol)
        
        var app: AppProtocol {
            get {
                switch self
                {
                case .install(let app), .refresh(let app): return app
                }
            }
            set {
                switch self
                {
                case .install: self = .install(newValue)
                case .refresh: self = .refresh(newValue)
                }
            }
        }
    }
    
    func progress(for operation: AppOperation) -> Progress?
    {
        func _progress() -> Progress?
        {
            switch operation
            {
            case .install(let app): return self.installationProgress[app.bundleIdentifier]
            case .refresh(let app): return self.refreshProgress[app.bundleIdentifier]
            }
        }
        
        if let context = (operation.app as? NSManagedObject)?.managedObjectContext
        {
            var progress: Progress?
            context.performAndWait { progress = _progress() }
            return progress
        }
        else
        {
            return _progress()
        }
    }
    
    func set(_ progress: Progress?, for operation: AppOperation)
    {
        func _setProgress()
        {
            switch operation
            {
            case .install(let app): self.installationProgress[app.bundleIdentifier] = progress
            case .refresh(let app): self.refreshProgress[app.bundleIdentifier] = progress
            }
        }
        
        if let context = (operation.app as? NSManagedObject)?.managedObjectContext
        {
            context.performAndWait { _setProgress() }
        }
        else
        {
            _setProgress()
        }
    }
    
    @discardableResult
    func install<T: AppProtocol>(_ app: T, presentingViewController: UIViewController?, context: AuthenticatedOperationContext = AuthenticatedOperationContext(), completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let group = RefreshGroup(context: context)
        group.completionHandler = { (result) in
            do
            {
                guard let (_, result) = try result.get().first else { throw OperationError.unknown }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        let operation = AppOperation.install(app)
        self.rst_perform([operation], presentingViewController: presentingViewController, group: group)
        
        return group.progress
    }
    
    @discardableResult
    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup? = nil) -> RefreshGroup
    {
        let group = group ?? RefreshGroup()
        
        let operations = installedApps.map { AppOperation.refresh($0) }
        return self.rst_perform(operations, presentingViewController: presentingViewController, group: group)
    }
    
    @discardableResult
    private func rst_perform(_ operations: [AppOperation], presentingViewController: UIViewController?, group: RefreshGroup) -> RefreshGroup
    {
        let operations = operations.filter { self.progress(for: $0) == nil || self.progress(for: $0)?.isCancelled == true }
        
        for operation in operations
        {
            let progress = Progress.discreteProgress(totalUnitCount: 100)
            self.set(progress, for: operation)
        }
        
        /* Authenticate (if necessary) */
        var authenticationOperation: AuthenticationOperation?
        if group.context.session == nil
        {
            authenticationOperation = self.rst_authenticate(presentingViewController: presentingViewController, context: group.context) { (result) in
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
                let bundleIdentifier = operation.app.bundleIdentifier
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
                
                func finish(_ result: Result<InstalledApp, Error>)
                {
                    print("Assigning results for \(bundleIdentifier)...")
                    
                    // Must remove before saving installedApp.
                    if let currentProgress = self.progress(for: operation), currentProgress == progress
                    {
                        // Only remove progress if it hasn't been replaced by another one.
                        self.set(nil, for: operation)
                    }
                    
                    do
                    {
                        let installedApp = try self.process(result, server: group.context.server)
                        group.set(.success(installedApp), forAppWithBundleIdentifier: installedApp.bundleIdentifier)
                        
                        if installedApp.bundleIdentifier == StoreApp.altstoreAppID
                        {
                            self.scheduleExpirationWarningLocalNotification(for: installedApp)
                        }
                        
                        do { try installedApp.managedObjectContext?.save() }
                        catch { print("Error saving installed app.", error) }
                    }
                    catch
                    {
                        group.set(.failure(error), forAppWithBundleIdentifier: bundleIdentifier)
                    }
                }
                
                switch operation
                {
                case .refresh(let installedApp as InstalledApp) where installedApp.certificateSerialNumber == group.context.certificate?.serialNumber:
                    // Refreshing apps, but using same certificate as last time, so we can just refresh provisioning profiles.
                                        
                    let refreshProgress = self.__rst_refresh(installedApp, group: group) { (result) in
                        finish(result)
                    }
                    progress?.addChild(refreshProgress, withPendingUnitCount: 80)
                    
                case .refresh(let app), .install(let app):
                    
                    let installProgress = self.__rst_install(app, group: group) { (result) in
                        finish(result)
                    }
                    progress?.addChild(installProgress, withPendingUnitCount: 80)
                }
            }
        }
        
        if let authenticationOperation = authenticationOperation
        {
            let awaitAuthenticationOperation = BlockOperation {
                print("Finished authenticated! Starting app operations...")
                
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
            self.run([awaitAuthenticationOperation])
        }
        else
        {
            performAppOperations()
        }
        
        return group
    }
    
    
    private func __rst_install(_ app: AppProtocol, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        let context = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: group.context)
        
        /* Download */
        let downloadOperation = DownloadAppOperation(app: app, context: context)
        downloadOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let app): context.app = app
            }
        }
        progress.addChild(downloadOperation.progress, withPendingUnitCount: 25)
        
        
        /* Refresh Anisette Data */
        let refreshAnisetteDataOperation = FetchAnisetteDataOperation(context: group.context)
        refreshAnisetteDataOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): context.error = error
            case .success(let anisetteData): group.context.session?.anisetteData = anisetteData
            }
        }
        refreshAnisetteDataOperation.addDependency(downloadOperation)
        
        
        /* Fetch Provisioning Profiles */
        let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
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
        
        let operations = [downloadOperation, refreshAnisetteDataOperation, fetchProvisioningProfilesOperation, resignAppOperation, sendAppOperation, installOperation]
        group.add(operations)
        self.run(operations)
        
        return progress
    }
    
    
    private func __rst_refresh(_ app: InstalledApp, group: RefreshGroup, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
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
            completionHandler(result)
        }
        progress.addChild(refreshAppOperation.progress, withPendingUnitCount: 40)
        refreshAppOperation.addDependency(fetchProvisioningProfilesOperation)
        
        let operations = [fetchProvisioningProfilesOperation, refreshAppOperation]
        group.add(operations)
        self.run(operations)
        
        return progress
    }
    
    
//    @discardableResult
//    private func rst_refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, refreshGroup: RefreshGroup? = nil) -> RefreshGroup
//    {
//        let apps = installedApps.filter { self.refreshProgress(for: $0) == nil || self.refreshProgress(for: $0)?.isCancelled == true }
//        let appBundleIDs = apps.map { $0.bundleIdentifier }
//
//        let group = refreshGroup ?? RefreshGroup()
//
//        var cleanUpToken: NSKeyValueObservation!
//        cleanUpToken = group.observe(\.isFinished) { (group, change) in
//            guard group.isFinished else { return }
//
//            // This will be called potentially multiple times, once per each call to refresh().
//            // As a result, make sure to _only_ clean up what we did in this specific call to refresh().
//
//            for bundleID in appBundleIDs
//            {
//                if let progress = self.refreshProgress[bundleID], progress == group.progress(forAppWithBundleIdentifier: bundleID)
//                {
//                    // Only remove progress if it hasn't been replaced by another one.
//                    self.refreshProgress[bundleID] = nil
//                }
//            }
//
//            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
//                guard let altstore = InstalledApp.fetchAltStore(in: context) else { return }
//                self.scheduleExpirationWarningLocalNotification(for: altstore)
//            }
//
//            // Explicitly reference token in closure to ensure it is strongly captured.
//            cleanUpToken.invalidate()
//        }
//
//        return self._prepare(apps, presentingViewController: presentingViewController, forceAppInstallation: false, group: group)
//    }
//
//    @discardableResult
//    private func _prepare(_ apps: [AppProtocol], presentingViewController: UIViewController?, forceAppInstallation: Bool, group: RefreshGroup) -> RefreshGroup
//    {
//        /* Authenticate (if necessary) */
//        var authenticationOperation: AuthenticationOperation?
//        if group.context.session == nil
//        {
//            authenticationOperation = self.rst_authenticate(presentingViewController: presentingViewController, context: group.context) { (result) in
//                switch result
//                {
//                case .failure(let error): group.context.error = error
//                case .success: break
//                }
//            }
//        }
//
//        /* Prepare Developer Account (if necessary) */
//        var prepareDeveloperAccountOperation: PrepareDeveloperAccountOperation?
//        if !group.didPrepareDeveloperAccount
//        {
//            prepareDeveloperAccountOperation = PrepareDeveloperAccountOperation(context: group.context)
//            prepareDeveloperAccountOperation?.resultHandler = { (result) in
//                switch result
//                {
//                case .failure(let error): group.context.error = error
//                case .success: group.didPrepareDeveloperAccount = true
//                }
//            }
//            authenticationOperation.map { prepareDeveloperAccountOperation?.addDependency($0) }
//        }
//
//        for app in apps
//        {
//            var context: AppOperationContext!
//
//            func finish(_ result: Result<InstalledApp, Error>)
//            {
//                do
//                {
//                    let installedApp = try self.process(result, server: group.context.server)
//                    installedApp.managedObjectContext?.performAndWait {
//                        group.set(.success(installedApp), forAppWithBundleIdentifier: installedApp.bundleIdentifier)
//
//                        // Must remove before saving installedApp.
//                        if let progress = self.refreshProgress[installedApp.bundleIdentifier], progress == group.progress(forAppWithBundleIdentifier: installedApp.bundleIdentifier)
//                        {
//                            // Only remove progress if it hasn't been replaced by another one.
//                            self.refreshProgress[installedApp.bundleIdentifier] = nil
//                        }
//
//                        do { try installedApp.managedObjectContext?.save() }
//                        catch { print("Error saving installed app.", error) }
//                    }
//                }
//                catch
//                {
//                    group.set(.failure(error), forAppWithBundleIdentifier: context.bundleIdentifier)
//                }
//            }
//
//            var shouldInstall = forceAppInstallation
//            if let installedApp = app as? InstalledApp, installedApp.certificateSerialNumber != group.context.certificate?.serialNumber
//            {
//                shouldInstall = true
//            }
//
//            if shouldInstall
//            {
//                context = self.__install(app, authenticatedContext: group.context) { (result) in
//                    finish(result)
//                }
//            }
//            else
//            {
//                context = self.__refresh(app, authenticatedContext: group.context) { (result) in
//                    finish(result)
//                }
//            }
//        }
//
//        return group
//    }
//
//    private func __install(_ app: AppProtocol, authenticatedContext: AuthenticatedOperationContext, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> InstallAppOperationContext
//    {
//        let context = InstallAppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: authenticatedContext)
//
//        let progress = Progress(totalUnitCount: 100)
//        self.installationProgress[app.bundleIdentifier] = progress
//
//        func finish(_ result: Result<InstalledApp, Error>)
//        {
//            if let installationProgress = self.installationProgress[app.bundleIdentifier], installationProgress == progress
//            {
//                // Only remove progress if it hasn't been replaced by another one.
//                self.installationProgress[app.bundleIdentifier] = nil
//            }
//
//            completionHandler(result)
//        }
//
//        /* Download */
//        let downloadOperation = DownloadAppOperation(app: app, context: context)
//        downloadOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let app): context.app = app
//            }
//        }
//        progress.addChild(downloadOperation.progress, withPendingUnitCount: 25)
//
//
//        /* Refresh Anisette Data */
//        let refreshAnisetteDataOperation = FetchAnisetteDataOperation(context: authenticatedContext)
//        refreshAnisetteDataOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let anisetteData): authenticatedContext.session?.anisetteData = anisetteData
//            }
//        }
//        refreshAnisetteDataOperation.addDependency(downloadOperation)
//
//
//        /* Fetch Provisioning Profiles */
//        let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
//        fetchProvisioningProfilesOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
//            }
//        }
//        fetchProvisioningProfilesOperation.addDependency(refreshAnisetteDataOperation)
//        progress.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 5)
//
//
//        /* Resign */
//        let resignAppOperation = ResignAppOperation(context: context)
//        resignAppOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let resignedApp): context.resignedApp = resignedApp
//            }
//        }
//        resignAppOperation.addDependency(fetchProvisioningProfilesOperation)
//        progress.addChild(resignAppOperation.progress, withPendingUnitCount: 20)
//
//
//        /* Send */
//        let sendAppOperation = SendAppOperation(context: context)
//        sendAppOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let installationConnection): context.installationConnection = installationConnection
//            }
//        }
//        sendAppOperation.addDependency(resignAppOperation)
//        progress.addChild(sendAppOperation.progress, withPendingUnitCount: 20)
//
//
//        /* Install */
//        let installOperation = InstallAppOperation(context: context)
//        installOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): finish(.failure(error))
//            case .success(let installedApp):
//                if let app = app as? StoreApp, let storeApp = installedApp.managedObjectContext?.object(with: app.objectID) as? StoreApp
//                {
//                    installedApp.storeApp = storeApp
//                }
//
//                finish(.success(installedApp))
//            }
//        }
//        progress.addChild(installOperation.progress, withPendingUnitCount: 30)
//        installOperation.addDependency(sendAppOperation)
//
//        self.run([downloadOperation, refreshAnisetteDataOperation, fetchProvisioningProfilesOperation, resignAppOperation, sendAppOperation, installOperation])
//        return context
//    }
//
//    private func __refresh(_ app: AppProtocol, authenticatedContext: AuthenticatedOperationContext, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> AppOperationContext
//    {
//        let context = AppOperationContext(bundleIdentifier: app.bundleIdentifier, authenticatedContext: authenticatedContext)
//        context.app = ALTApplication(fileURL: app.url)
//
//        let progress = self.refreshProgress[app.bundleIdentifier]
//        progress?.completedUnitCount += 30
//
//        /* Fetch Provisioning Profiles */
//        let fetchProvisioningProfilesOperation = FetchProvisioningProfilesOperation(context: context)
//        fetchProvisioningProfilesOperation.resultHandler = { (result) in
//            switch result
//            {
//            case .failure(let error): context.error = error
//            case .success(let provisioningProfiles): context.provisioningProfiles = provisioningProfiles
//            }
//        }
//        progress?.addChild(fetchProvisioningProfilesOperation.progress, withPendingUnitCount: 40)
//
//
//        /* Refresh */
//        let refreshAppOperation = RefreshAppOperation(context: context)
//        refreshAppOperation.resultHandler = { (result) in
//            completionHandler(result)
//        }
//        progress?.addChild(refreshAppOperation.progress, withPendingUnitCount: 30)
//        refreshAppOperation.addDependency(fetchProvisioningProfilesOperation)
//
//        self.run([fetchProvisioningProfilesOperation, refreshAppOperation])
//        return context
//    }
    
    @discardableResult func process<T>(_ result: Result<T, Error>, server: Server?) throws -> T
    {
        do
        {
            let value = try result.get()
            return value
        }
        catch let error as ALTServerError where error.code == .deviceNotFound || error.code == .lostConnection
        {
            if let server = server, server.isPreferred || server.isWiredConnection
            {
                // Preferred server (or wired connection), so report errors normally.
                throw error
            }
            else
            {
                // Not preferred server, so ignore these specific errors and throw serverNotFound instead.
                throw ConnectionError.serverNotFound
            }
        }
        catch
        {
            throw error
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
    
    func run(_ operations: [Foundation.Operation])
    {
        for operation in operations
        {
            switch operation
            {
            case is InstallAppOperation, is RefreshAppOperation:
                if let previousOperation = self.serialOperationQueue.operations.last
                {
                    // Ensure operations execute in the order they're added, since they may become ready at different points.
                    operation.addDependency(previousOperation)
                }
                
                self.serialOperationQueue.addOperation(operation)
                
            default:
                self.operationQueue.addOperation(operation)
            }
        }
    }
}
