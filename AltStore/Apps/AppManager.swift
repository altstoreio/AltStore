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
    func install(_ app: App, presentingViewController: UIViewController, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        // Authenticate
        let authenticationOperation = AuthenticationOperation(presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let signer):
                
                // Download
                app.managedObjectContext?.perform {
                    let downloadAppOperation = DownloadAppOperation(app: app)
                    downloadAppOperation.resultHandler = { (result) in
                        switch result
                        {
                        case .failure(let error): completionHandler(.failure(error))
                        case .success(let installedApp):
                            let context = installedApp.managedObjectContext
                            
                            // Refresh/Install
                            let (resignProgress, installProgress) = self.refresh(installedApp, signer: signer, presentingViewController: presentingViewController) { (result) in
                                switch result
                                {
                                case .failure(let error): completionHandler(.failure(error))
                                case .success:
                                    context?.perform {
                                        completionHandler(.success(installedApp))
                                    }
                                }
                            }
                            progress.addChild(resignProgress, withPendingUnitCount: 10)
                            progress.addChild(installProgress, withPendingUnitCount: 45)
                        }
                    }
                    progress.addChild(downloadAppOperation.progress, withPendingUnitCount: 40)
                    self.operationQueue.addOperation(downloadAppOperation)
                }
            }
        }
        progress.addChild(authenticationOperation.progress, withPendingUnitCount: 5)
        self.operationQueue.addOperation(authenticationOperation)
        
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
        let progress = Progress.discreteProgress(totalUnitCount: Int64(installedApps.count))
        
        guard let context = installedApps.first?.managedObjectContext else {
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
                
                // Refresh
                context.perform {
                    let dispatchGroup = DispatchGroup()
                    var results = [String: Result<InstalledApp, Error>]()
                    
                    for installedApp in installedApps
                    {
                        let bundleIdentifier = installedApp.bundleIdentifier
                        print("Refreshing App:", bundleIdentifier)
                        
                        dispatchGroup.enter()
                        
                        let (resignProgress, installProgress) = self.refresh(installedApp, signer: signer, presentingViewController: presentingViewController) { (result) in
                            print("Refreshed App: \(bundleIdentifier).", result)
                            results[bundleIdentifier] = result
                            dispatchGroup.leave()
                        }
                        
                        let refreshProgress = Progress(totalUnitCount: 100)
                        refreshProgress.addChild(resignProgress, withPendingUnitCount: 20)
                        refreshProgress.addChild(installProgress, withPendingUnitCount: 80)
                        
                        progress.addChild(refreshProgress, withPendingUnitCount: 1)
                    }
                    
                    dispatchGroup.notify(queue: .global()) {
                        context.perform {
                            completionHandler(.success(results))
                        }
                    }
                }
            }
        }
        
        self.operationQueue.addOperation(authenticationOperation)
        
        return progress
    }
}

private extension AppManager
{
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
