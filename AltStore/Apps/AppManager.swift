//
//  AppManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import UIKit

import AltSign
import AltKit

import Roxas

extension AppManager
{
    static let didFetchAppsNotification = Notification.Name("com.altstore.AppManager.didFetchApps")
}

class AppManager
{
    static let shared = AppManager()
    
    private let operationQueue = OperationQueue()
    
    private init()
    {
        self.operationQueue.name = "com.rileytestut.AltStore.AppManager"
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
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
        
        do
        {
            let installedApps = try context.fetch(fetchRequest)
            for app in installedApps
            {
                if UIApplication.shared.canOpenURL(app.openAppURL)
                {
                    // App is still installed, good!
                }
                else
                {
                    context.delete(app)
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
    
    func authenticate(presentingViewController: UIViewController?, completionHandler: @escaping (Result<ALTSigner, Error>) -> Void)
    {
        let authenticationOperation = AuthenticationOperation(presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            completionHandler(result)
        }
        self.operationQueue.addOperation(authenticationOperation)
    }
}

extension AppManager
{
    func fetchApps(completionHandler: @escaping (Result<[App], Error>) -> Void)
    {
        let fetchAppsOperation = FetchAppsOperation()
        fetchAppsOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error):
                completionHandler(.failure(error))
                
            case .success(let apps):
                completionHandler(.success(apps))
                NotificationCenter.default.post(name: AppManager.didFetchAppsNotification, object: self)
            }
        }
        self.operationQueue.addOperation(fetchAppsOperation)
    }
}

extension AppManager
{
    func install(_ app: App, presentingViewController: UIViewController, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = self.install([app], forceDownload: true, presentingViewController: presentingViewController) { (result) in
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
        
        return progress
    }
    
    func refresh(_ app: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        return self.refresh([app], presentingViewController: presentingViewController) { (result) in
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
    }
    
    @discardableResult func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void) -> Progress
    {
        let apps = installedApps.compactMap { $0.app }
        
        let progress = self.install(apps, forceDownload: false, presentingViewController: presentingViewController, completionHandler: completionHandler)
        return progress
    }
}

private extension AppManager
{
    func install(_ apps: [App], forceDownload: Bool, presentingViewController: UIViewController?, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: Int64(apps.count))
        
        guard let context = apps.first?.managedObjectContext else {
            completionHandler(.success([:]))
            return progress
        }
        
        // Authenticate
        let authenticationOperation = AuthenticationOperation(presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let signer):
                
                // Download
                context.perform {
                    let dispatchGroup = DispatchGroup()
                    var results = [String: Result<InstalledApp, Error>]()
                    
                    let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                    
                    for app in apps
                    {
                        let appProgress = Progress(totalUnitCount: 100)
                        
                        let appID = app.identifier
                        print("Installing app:", appID)
                        
                        dispatchGroup.enter()
                        
                        func finishApp(_ result: Result<InstalledApp, Error>)
                        {
                            switch result
                            {
                            case .failure(let error): print("Failed to install app \(appID).", error)
                            case .success: print("Installed app:", appID)
                            }
                            
                            results[appID] = result
                            dispatchGroup.leave()
                        }
                        
                        // Ensure app is downloaded.
                        let downloadAppOperation = DownloadAppOperation(app: app)
                        downloadAppOperation.useCachedAppIfAvailable = !forceDownload
                        downloadAppOperation.context = backgroundContext
                        downloadAppOperation.resultHandler = { (result) in
                            switch result
                            {
                            case .failure(let error):
                                finishApp(.failure(error))
                                
                            case .success(let installedApp):
                                
                                // Refresh
                                let (resignProgress, installProgress) = self.refresh(installedApp, signer: signer, presentingViewController: presentingViewController) { (result) in
                                    finishApp(result)
                                }
                                
                                if forceDownload
                                {
                                    appProgress.addChild(resignProgress, withPendingUnitCount: 10)
                                    appProgress.addChild(installProgress, withPendingUnitCount: 50)
                                }
                                else
                                {
                                    appProgress.addChild(resignProgress, withPendingUnitCount: 20)
                                    appProgress.addChild(installProgress, withPendingUnitCount: 80)
                                }
                            }
                        }
                        
                        if forceDownload
                        {
                            appProgress.addChild(downloadAppOperation.progress, withPendingUnitCount: 40)
                        }
                        
                        progress.addChild(appProgress, withPendingUnitCount: 1)
                        
                        self.operationQueue.addOperation(downloadAppOperation)
                    }
                    
                    dispatchGroup.notify(queue: .global()) {
                        backgroundContext.perform {
                            completionHandler(.success(results))
                        }
                    }
                }
            }
        }
        
        self.operationQueue.addOperation(authenticationOperation)
        
        return progress
    }
    
    func refresh(_ installedApp: InstalledApp, signer: ALTSigner, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> (Progress, Progress)
    {
        let context = installedApp.managedObjectContext
        
        let resignAppOperation = ResignAppOperation(installedApp: installedApp)
        let installAppOperation = InstallAppOperation()
        
        // Resign
        resignAppOperation.signer = signer
        resignAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error):
                installAppOperation.cancel()
                completionHandler(.failure(error))
                
            case .success(let resignedURL):
                installAppOperation.fileURL = resignedURL
            }
        }
        
        // Install
        installAppOperation.addDependency(resignAppOperation)
        installAppOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success:
                context?.perform {
                    completionHandler(.success(installedApp))
                }
            }
        }
        
        self.operationQueue.addOperations([resignAppOperation, installAppOperation], waitUntilFinished: false)
        
        return (resignAppOperation.progress, installAppOperation.progress)
    }
}
