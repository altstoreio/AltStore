//
//  AppDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import UserNotifications
import AVFoundation

import AltSign
import Roxas

private extension CFNotificationName
{
    static let requestAppState = CFNotificationName("com.altstore.RequestAppState" as CFString)
    static let appIsRunning = CFNotificationName("com.altstore.AppState.Running" as CFString)
    
    static func requestAppState(for appID: String) -> CFNotificationName
    {
        let name = String(CFNotificationName.requestAppState.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }
    
    static func appIsRunning(for appID: String) -> CFNotificationName
    {
        let name = String(CFNotificationName.appIsRunning.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }
}

private let ReceivedApplicationState: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void =
{ (center, observer, name, object, userInfo) in
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate, let name = name else { return }
    appDelegate.receivedApplicationState(notification: name)
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    private var runningApplications: Set<String>?
    private var isLaunching = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        self.isLaunching = true
        
        ServerManager.shared.startDiscovering()
        
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                print("Failed to start DatabaseManager.", error)
            }
            else
            {
                print("Started DatabaseManager")
                
                DispatchQueue.main.async {
                    AppManager.shared.update()
                }
            }
        }
        
        if UserDefaults.standard.firstLaunch == nil
        {
            Keychain.shared.reset()
            UserDefaults.standard.firstLaunch = Date()
        }
        
        self.prepareForBackgroundFetch()
        
        DispatchQueue.main.async {
            self.isLaunching = false
        }
                
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication)
    {
        ServerManager.shared.stopDiscovering()
    }

    func applicationWillEnterForeground(_ application: UIApplication)
    {
        AppManager.shared.update()
        ServerManager.shared.startDiscovering()
    }
}

extension AppDelegate
{
    private func prepareForBackgroundFetch()
    {
        // "Fetch" every hour, but then refresh only those that need to be refreshed (so we don't drain the battery).
        UIApplication.shared.setMinimumBackgroundFetchInterval(60 * 60)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (success, error) in
        }
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        let isLaunching = self.isLaunching
        
        let installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: DatabaseManager.shared.viewContext)
        guard !installedApps.isEmpty else {
            ServerManager.shared.stopDiscovering()
            completionHandler(.noData)
            return
        }
        
        self.runningApplications = []
        
        let identifiers = installedApps.compactMap { $0.app?.identifier }
        print("Apps to refresh:", identifiers)
        
        DispatchQueue.global().async {
            let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
            
            for identifier in identifiers
            {
                let appIsRunningNotification = CFNotificationName.appIsRunning(for: identifier)
                CFNotificationCenterAddObserver(notificationCenter, nil, ReceivedApplicationState, appIsRunningNotification.rawValue, nil, .deliverImmediately)
                
                let requestAppStateNotification = CFNotificationName.requestAppState(for: identifier)
                CFNotificationCenterPostNotification(notificationCenter, requestAppStateNotification, nil, nil, true)
            }
        }
        
        BackgroundTaskManager.shared.performExtendedBackgroundTask { (taskResult, taskCompletionHandler) in
            
            func finish(_ result: Result<[String: Result<InstalledApp, Error>], Error>)
            {
                ServerManager.shared.stopDiscovering()
                
                let content = UNMutableNotificationContent()
                var shouldPresentAlert = true
                
                do
                {
                    let results = try result.get()
                    shouldPresentAlert = !results.isEmpty
                    
                    for (_, result) in results
                    {
                        guard case let .failure(error) = result else { continue }
                        throw error
                    }
                    
                    content.title = NSLocalizedString("Refreshed all apps!", comment: "")
                }
                catch let error as NSError where
                    (error.domain == NSOSStatusErrorDomain || error.domain == AVFoundationErrorDomain) &&
                    error.code == AVAudioSession.ErrorCode.cannotStartPlaying.rawValue &&
                    !isLaunching
                {
                    // We can only start background audio when the app is being launched,
                    // and _not_ if it's already suspended in background.
                    // Since we are currently suspended in background and not launching, we'll just ignore the error.
                    
                    shouldPresentAlert = false
                    
                    #if DEBUG
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                    content.body = NSLocalizedString("AltStore is currently suspended in the background.", comment: "")
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                    #endif
                }
                catch
                {
                    print("Failed to refresh apps in background.", error)
                    
                    content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                    content.body = error.localizedDescription
                    
                    shouldPresentAlert = true
                }
                
                if shouldPresentAlert
                {
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                
                switch result
                {
                case .failure(ConnectionError.serverNotFound): completionHandler(.newData)
                case .failure: completionHandler(.failed)
                case .success: completionHandler(.newData)
                }
                
                taskCompletionHandler()
            }
            
            #if DEBUG
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Refreshing apps...", comment: "")
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            #endif
            
            if let error = taskResult.error
            {
                print("Error starting extended background task. Aborting.", error)
                finish(.failure(error))
                return
            }
            
            // Wait for three seconds to:
            // a) give us time to discover AltServers
            // b) give other processes a chance to respond to requestAppState notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let filteredApps = installedApps.filter { !(self.runningApplications?.contains($0.app.identifier) ?? false) }
                print("Filtered Apps to Refresh:", filteredApps.map { $0.app.identifier })
                
                let group = AppManager.shared.refresh(filteredApps, presentingViewController: nil)
                group.beginInstallationHandler = { (installedApp) in
                    guard installedApp.app.identifier == App.altstoreAppID else { return }
                    
                    // We're starting to install AltStore, which means the app is about to quit.
                    // So, we say we were successful even though we technically don't know 100% yet.
                    // Also since AltServer has already received the app, it can finish installing even if we're no longer running in background.
                    
                    if let error = group.error
                    {
                        finish(.failure(error))
                    }
                    else
                    {
                        var results = group.results
                        results[installedApp.app.identifier] = .success(installedApp)
                        
                        finish(.success(results))
                    }
                }
                group.completionHandler = { (result) in
                    finish(result)
                }
            }
        }
    }
    
    func receivedApplicationState(notification: CFNotificationName)
    {
        let baseName = String(CFNotificationName.appIsRunning.rawValue)
        
        let appID = String(notification.rawValue).replacingOccurrences(of: baseName + ".", with: "")
        self.runningApplications?.insert(appID)
    }
}
