//
//  AppDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import UserNotifications

import AltSign
import Roxas

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
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
        let installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: DatabaseManager.shared.viewContext)
        guard !installedApps.isEmpty else { return completionHandler(.noData) }
        
        print("Apps to refresh:", installedApps.map { $0.app.identifier })
        
        ServerManager.shared.startDiscovering()
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Refreshing apps...", comment: "")
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { (error) in
            if let error = error {
                print(error)
            }
        }
        
        // Wait a few seconds so we have a chance to discover nearby AltServers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            
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
                catch
                {
                    print("Failed to refresh apps in background.", error)
                    
                    content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                    content.body = error.localizedDescription
                    
                    shouldPresentAlert = true
                }
                
                if shouldPresentAlert
                {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request) { (error) in
                        if let error = error {
                            print(error)
                        }
                    }
                }
                
                switch result
                {
                case .failure(ConnectionError.serverNotFound): completionHandler(.newData)
                case .failure: completionHandler(.failed)
                case .success: completionHandler(.newData)
                }
            }
            
            let group = AppManager.shared.refresh(installedApps, presentingViewController: nil)
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
