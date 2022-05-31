//
//  AppDelegate.swift
//  AltBackup
//
//  Created by Riley Testut on 5/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

extension AppDelegate
{
    static let startBackupNotification = Notification.Name("io.altstore.StartBackup")
    static let startRestoreNotification = Notification.Name("io.altstore.StartRestore")
    
    static let operationDidFinishNotification = Notification.Name("io.altstore.BackupOperationFinished")
    
    static let operationResultKey = "result"
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    private var currentBackupReturnURL: URL?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        // Override point for customization after application launch.
        
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.operationDidFinish(_:)), name: AppDelegate.operationDidFinishNotification, object: nil)
        
        let viewController = ViewController()
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = viewController
        self.window?.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
    {
        return self.open(url)
    }
}

private extension AppDelegate
{
    func open(_ url: URL) -> Bool
    {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard let command = components.host?.lowercased() else { return false }
        
        switch command
        {
        case "backup":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startBackupNotification, object: nil)
            
            return true
            
        case "restore":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startRestoreNotification, object: nil)
            
            return true
            
        default: return false
        }
    }
    
    @objc func operationDidFinish(_ notification: Notification)
    {
        defer { self.currentBackupReturnURL = nil }
        
        guard
            let returnURL = self.currentBackupReturnURL,
            let result = notification.userInfo?[AppDelegate.operationResultKey] as? Result<Void, Error>
        else { return }
                
        guard var components = URLComponents(url: returnURL, resolvingAgainstBaseURL: false) else { return }
        
        switch result
        {
        case .success:
            components.path = "/success"
            
        case .failure(let error as NSError):
            components.path = "/failure"
            components.queryItems = ["errorDomain": error.domain,
                                     "errorCode": String(error.code),
                                     "errorDescription": error.localizedDescription].map { URLQueryItem(name: $0, value: $1) }
        }
        
        guard let responseURL = components.url else { return }
        
        DispatchQueue.main.async {
            UIApplication.shared.open(responseURL, options: [:]) { (success) in
                print("Sent response to app with success:", success)
            }
        }
    }
}

