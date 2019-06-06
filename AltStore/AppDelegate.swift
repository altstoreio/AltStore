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
                
                AppManager.shared.update()
            }
        }
        
        if UserDefaults.standard.firstLaunch == nil
        {
            Keychain.shared.appleIDEmailAddress = nil
            Keychain.shared.appleIDPassword = nil
            Keychain.shared.signingCertificatePrivateKey = nil
            Keychain.shared.signingCertificateIdentifier = nil
            
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
        // Fetch every 6 hours.
        UIApplication.shared.setMinimumBackgroundFetchInterval(60 * 60 * 6)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (success, error) in
        }
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        ServerManager.shared.startDiscovering()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppManager.shared.refreshAllApps() { (result) in
                ServerManager.shared.stopDiscovering()
                
                let content = UNMutableNotificationContent()
                
                do
                {
                    let results = try result.get()
                    
                    for (_, result) in results
                    {
                        guard case let .failure(error) = result else { continue }
                        throw error
                    }
                    
                    print(results)
                    
                    content.title = "Refreshed Apps!"
                    content.body = "Successfully refreshed all apps."
                    
                    completionHandler(.newData)
                }
                catch
                {
                    print("Failed to refresh apps in background.", error)
                    
                    content.title = "Failed to Refresh Apps"
                    content.body = error.localizedDescription
                    
                    completionHandler(.failed)
                }
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                
                let request = UNNotificationRequest(identifier: "RefreshedApps", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { (error) in
                    if let error = error {
                        print(error)
                    }
                }
            }
        }
    }
}
