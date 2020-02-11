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
    private let processingQueue = DispatchQueue(label: "com.altstore.AppManager.processingQueue")
    
    private var installationProgress = [String: Progress]()
    private var refreshProgress = [String: Progress]()
    
    private init()
    {
        self.operationQueue.name = "com.altstore.AppManager.operationQueue"
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
    
    @discardableResult
    func authenticate(presentingViewController: UIViewController?, completionHandler: @escaping (Result<(ALTSigner, ALTAppleAPISession), Error>) -> Void) -> OperationGroup
    {
        let group = OperationGroup()
        
        let findServerOperation = FindServerOperation(group: group)
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): group.error = error
            case .success(let server): group.server = server
            }
        }
        self.operationQueue.addOperation(findServerOperation)
        
        let authenticationOperation = AuthenticationOperation(group: group, presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): group.error = error
            case .success(let signer, let session):
                group.signer = signer
                group.session = session
            }
            
            completionHandler(result)
        }
        authenticationOperation.addDependency(findServerOperation)
        self.operationQueue.addOperation(authenticationOperation)
        
        return group
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
            self.operationQueue.addOperation(fetchSourceOperation)
        }
    }
    
    func fetchAppIDs(completionHandler: @escaping (Result<([AppID], NSManagedObjectContext), Error>) -> Void)
    {
        var group: OperationGroup!
        group = self.authenticate(presentingViewController: nil) { (result) in
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success:
                let fetchAppIDsOperation = FetchAppIDsOperation(group: group)
                fetchAppIDsOperation.resultHandler = completionHandler
                self.operationQueue.addOperation(fetchAppIDsOperation)
            }
        }
    }
}

extension AppManager
{
    func install(_ app: AppProtocol, presentingViewController: UIViewController, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        if let progress = self.installationProgress(for: app)
        {
            return progress
        }
        
        let bundleIdentifier = app.bundleIdentifier
        
        let group = self.install([app], forceDownload: true, presentingViewController: presentingViewController)
        group.completionHandler = { (result) in            
            do
            {
                self.installationProgress[bundleIdentifier] = nil
                
                guard let (_, result) = try result.get().first else { throw OperationError.unknown }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        self.installationProgress[bundleIdentifier] = group.progress
        
        return group.progress
    }
    
    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: OperationGroup? = nil) -> OperationGroup
    {
        let apps = installedApps.filter { self.refreshProgress(for: $0) == nil || self.refreshProgress(for: $0)?.isCancelled == true }

        let group = self.install(apps, forceDownload: false, presentingViewController: presentingViewController, group: group)
        
        for app in apps
        {
            guard let progress = group.progress(for: app) else { continue }
            self.refreshProgress[app.bundleIdentifier] = progress
        }
        
        return group
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

private extension AppManager
{
    func install(_ apps: [AppProtocol], forceDownload: Bool, presentingViewController: UIViewController?, group: OperationGroup? = nil) -> OperationGroup
    {
        // Authenticate -> Download (if necessary) -> Resign -> Send -> Install.
        let group = group ?? OperationGroup()
        var operations = [Operation]()
        
        /* Find Server */
        let findServerOperation = FindServerOperation(group: group)
        findServerOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): group.error = error
            case .success(let server): group.server = server
            }
        }
        operations.append(findServerOperation)
        
        let authenticationOperation: AuthenticationOperation?
        
        if group.signer == nil || group.session == nil
        {
            /* Authenticate */
            let operation = AuthenticationOperation(group: group, presentingViewController: presentingViewController)
            operation.resultHandler = { (result) in
                switch result
                {
                case .failure(let error): group.error = error
                case .success(let signer, let session):
                    group.signer = signer
                    group.session = session
                }
            }
            operations.append(operation)
            operation.addDependency(findServerOperation)
            
            authenticationOperation = operation
        }
        else
        {
            authenticationOperation = nil
        }
        
        let refreshAnisetteDataOperation = FetchAnisetteDataOperation(group: group)
        refreshAnisetteDataOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): group.error = error
            case .success(let anisetteData): group.session?.anisetteData = anisetteData
            }
        }
        refreshAnisetteDataOperation.addDependency(authenticationOperation ?? findServerOperation)
        operations.append(refreshAnisetteDataOperation)
        
        /* Prepare Developer Account */
        let prepareDeveloperAccountOperation = PrepareDeveloperAccountOperation(group: group)
        prepareDeveloperAccountOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): group.error = error
            case .success: break
            }
        }
        prepareDeveloperAccountOperation.addDependency(refreshAnisetteDataOperation)
        operations.append(prepareDeveloperAccountOperation)
        
        for app in apps
        {
            let context = AppOperationContext(bundleIdentifier: app.bundleIdentifier, group: group)
            let progress = Progress.discreteProgress(totalUnitCount: 100)
            
            
            /* Resign */
            let resignAppOperation = ResignAppOperation(context: context)
            resignAppOperation.resultHandler = { (result) in
                guard let resignedApp = self.process(result, context: context) else { return }
                context.resignedApp = resignedApp
            }
            resignAppOperation.addDependency(prepareDeveloperAccountOperation)
            progress.addChild(resignAppOperation.progress, withPendingUnitCount: 20)
            operations.append(resignAppOperation)
            
            
            /* Download */
            let fileURL = InstalledApp.fileURL(for: app)
            
            var localApp: ALTApplication?
            
            let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            managedObjectContext.performAndWait {
                let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), context.bundleIdentifier)
                
                if let installedApp = InstalledApp.first(satisfying: predicate, in: managedObjectContext), FileManager.default.fileExists(atPath: fileURL.path), !forceDownload
                {
                    localApp = ALTApplication(fileURL: installedApp.fileURL)
                }
            }
        
            if let localApp = localApp
            {
                // Already installed, don't need to download.
                
                // If we don't need to download the app, reduce the total unit count by 40.
                progress.totalUnitCount -= 40
                
                context.app = localApp
            }
            else
            {
                // App is not yet installed (or we're forcing it to download a new version), so download it before resigning it.
                
                let downloadOperation = DownloadAppOperation(app: app, context: context)
                downloadOperation.resultHandler = { (result) in
                    guard let app = self.process(result, context: context) else { return }
                    context.app = app
                }
                progress.addChild(downloadOperation.progress, withPendingUnitCount: 40)
                downloadOperation.addDependency(findServerOperation)
                resignAppOperation.addDependency(downloadOperation)
                operations.append(downloadOperation)
            }
            
            /* Send */
            let sendAppOperation = SendAppOperation(context: context)
            sendAppOperation.resultHandler = { (result) in
                guard let installationConnection = self.process(result, context: context) else { return }
                context.installationConnection = installationConnection
            }
            progress.addChild(sendAppOperation.progress, withPendingUnitCount: 10)
            sendAppOperation.addDependency(resignAppOperation)
            operations.append(sendAppOperation)
            
            
            let beginInstallationHandler = group.beginInstallationHandler
            group.beginInstallationHandler = { (installedApp) in
                if installedApp.bundleIdentifier == StoreApp.altstoreAppID
                {
                    self.scheduleExpirationWarningLocalNotification(for: installedApp)
                }
                
                beginInstallationHandler?(installedApp)
            }
            
            /* Install */
            let installOperation = InstallAppOperation(context: context)
            installOperation.resultHandler = { (result) in
                if let error = result.error
                {
                    context.error = error
                }
                
                if let installedApp = result.value
                {
                    if let app = app as? StoreApp, let storeApp = installedApp.managedObjectContext?.object(with: app.objectID) as? StoreApp
                    {
                        installedApp.storeApp = storeApp
                    }
                    
                    context.installedApp = installedApp
                }
                
                self.finishAppOperation(context) // Finish operation no matter what.
            }
            progress.addChild(installOperation.progress, withPendingUnitCount: 30)
            installOperation.addDependency(sendAppOperation)
            operations.append(installOperation)
                        
            group.set(progress, for: app)
        }
        
        // Refresh anisette data after downloading all apps to prevent session from expiring.
        for case let downloadOperation as DownloadAppOperation in operations
        {
            refreshAnisetteDataOperation.addDependency(downloadOperation)
        }
        
        /* Cache App IDs */
        let fetchAppIDsOperation = FetchAppIDsOperation(group: group)
        fetchAppIDsOperation.resultHandler = { (result) in
            do
            {
                let (_, context) = try result.get()
                try context.save()
            }
            catch
            {
                print("Failed to fetch App IDs.", error)
            }
        }
        operations.forEach { fetchAppIDsOperation.addDependency($0) }
        operations.append(fetchAppIDsOperation)
        
        group.addOperations(operations)
        
        return group
    }
    
    @discardableResult func process<T>(_ result: Result<T, Error>, context: AppOperationContext) -> T?
    {
        do
        {            
            let value = try result.get()
            return value
        }
        catch OperationError.cancelled
        {
            context.error = OperationError.cancelled
            self.finishAppOperation(context)
            
            return nil
        }
        catch
        {
            context.error = error
            return nil
        }
    }
    
    func finishAppOperation(_ context: AppOperationContext)
    {
        self.processingQueue.sync {
            guard !context.isFinished else { return }
            context.isFinished = true
            
            if let progress = self.refreshProgress[context.bundleIdentifier], progress == context.group.progress(forAppWithBundleIdentifier: context.bundleIdentifier)
            {
                // Only remove progress if it hasn't been replaced by another one.
                self.refreshProgress[context.bundleIdentifier] = nil
            }
            
            if let error = context.error
            {
                switch error
                {
                case let error as ALTServerError where error.code == .deviceNotFound || error.code == .lostConnection:
                    if let server = context.group.server, server.isPreferred
                    {
                        // Preferred server, so report errors normally.
                        context.group.results[context.bundleIdentifier] = .failure(error)
                    }
                    else
                    {
                        // Not preferred server, so ignore these specific errors and throw serverNotFound instead.
                        context.group.results[context.bundleIdentifier] = .failure(ConnectionError.serverNotFound)
                    }
                    
                case let error:
                    context.group.results[context.bundleIdentifier] = .failure(error)
                }
                
            }
            else if let installedApp = context.installedApp
            {
                context.group.results[context.bundleIdentifier] = .success(installedApp)
                
                // Save after each installation.
                installedApp.managedObjectContext?.performAndWait {
                    do { try installedApp.managedObjectContext?.save() }
                    catch { print("Error saving installed app.", error) }
                }
                
                if let index = UserDefaults.standard.legacySideloadedApps?.firstIndex(of: installedApp.bundleIdentifier)
                {
                    // No longer a legacy sideloaded app, so remove it from cached list.
                    UserDefaults.standard.legacySideloadedApps?.remove(at: index)
                }
            }            
            
            print("Finished operation!", context.bundleIdentifier)

            if context.group.results.count == context.group.progress.totalUnitCount
            {
                context.group.completionHandler?(.success(context.group.results))
                
                let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                backgroundContext.performAndWait {
                    guard let altstore = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID), in: backgroundContext) else { return }
                    self.scheduleExpirationWarningLocalNotification(for: altstore)
                }
            }
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
}
