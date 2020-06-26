//
//  BackupAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign

extension BackupAppOperation
{
    enum Action: String
    {
        case backup
        case restore
    }
}

@objc(BackupAppOperation)
class BackupAppOperation: ResultOperation<Void>
{
    let action: Action
    let context: InstallAppOperationContext
    
    private var appName: String?
    private var timeoutTimer: Timer?
    
    init(action: Action, context: InstallAppOperationContext)
    {
        self.action = action
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            guard let installedApp = self.context.installedApp, let context = installedApp.managedObjectContext else { throw OperationError.invalidParameters }
            context.perform {
                do
                {
                    let appName = installedApp.name
                    self.appName = appName
                    
                    guard let altstoreApp = InstalledApp.fetchAltStore(in: context) else { throw OperationError.appNotFound }
                    let altstoreOpenURL = altstoreApp.openAppURL
                    
                    var returnURLComponents = URLComponents(url: altstoreOpenURL, resolvingAgainstBaseURL: false)
                    returnURLComponents?.host = "appBackupResponse"
                    guard let returnURL = returnURLComponents?.url else { throw OperationError.openAppFailed(name: appName) }
                    
                    var openURLComponents = URLComponents()
                    openURLComponents.scheme = installedApp.openAppURL.scheme
                    openURLComponents.host = self.action.rawValue
                    openURLComponents.queryItems = [URLQueryItem(name: "returnURL", value: returnURL.absoluteString)]
                    
                    guard let openURL = openURLComponents.url else { throw OperationError.openAppFailed(name: appName) }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let currentTime = CFAbsoluteTimeGetCurrent()
                        
                        UIApplication.shared.open(openURL, options: [:]) { (success) in
                            let elapsedTime = CFAbsoluteTimeGetCurrent() - currentTime
                            
                            if success
                            {
                                self.registerObservers()
                            }
                            else if elapsedTime < 0.5
                            {
                                // Failed too quickly for human to respond to alert, possibly still finalizing installation.
                                // Try again in a couple seconds.
                                
                                print("Failed too quickly, retrying after a few seconds...")
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    UIApplication.shared.open(openURL, options: [:]) { (success) in
                                        if success
                                        {
                                            self.registerObservers()
                                        }
                                        else
                                        {
                                            self.finish(.failure(OperationError.openAppFailed(name: appName)))
                                        }
                                    }
                                }
                            }
                            else
                            {
                                self.finish(.failure(OperationError.openAppFailed(name: appName)))
                            }
                        }
                    }
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
    
    override func finish(_ result: Result<Void, Error>)
    {
        let result = result.mapError { (error) -> Error in
            let appName = self.appName ?? self.context.bundleIdentifier
            
            switch (error, self.action)
            {
            case (let error as NSError, _) where (self.context.error as NSError?) == error: fallthrough
            case (OperationError.cancelled, _):
                return error
                
            case (let error as NSError, .backup):
                let localizedFailure = String(format: NSLocalizedString("Could not back up “%@”.", comment: ""), appName)
                return error.withLocalizedFailure(localizedFailure)
                
            case (let error as NSError, .restore):
                let localizedFailure = String(format: NSLocalizedString("Could not restore “%@”.", comment: ""), appName)
                return error.withLocalizedFailure(localizedFailure)
            }
        }
        
        switch result
        {
        case .success: self.progress.completedUnitCount += 1
        case .failure: break
        }
        
        super.finish(result)
    }
}

private extension BackupAppOperation
{
    func registerObservers()
    {
        var applicationWillReturnObserver: NSObjectProtocol!
        applicationWillReturnObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] (notification) in
            guard let self = self, !self.isFinished else { return }
            
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] (timer) in
                // Final delay to ensure we don't prematurely return failure
                // in case timer expired while we were in background, but
                // are now returning to app with success response.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let self = self, !self.isFinished else { return }
                    self.finish(.failure(OperationError.timedOut))
                }
            }
            
            NotificationCenter.default.removeObserver(applicationWillReturnObserver!)
        }
        
        var backupResponseObserver: NSObjectProtocol!
        backupResponseObserver = NotificationCenter.default.addObserver(forName: AppDelegate.appBackupDidFinish, object: nil, queue: nil) { [weak self] (notification) in
            self?.timeoutTimer?.invalidate()
            
            let result = notification.userInfo?[AppDelegate.appBackupResultKey] as? Result<Void, Error> ?? .failure(OperationError.unknownResult)
            self?.finish(result)
            
            NotificationCenter.default.removeObserver(backupResponseObserver!)
        }
    }
}
