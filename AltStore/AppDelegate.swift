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
import Intents

import AltStoreCore
import AltSign
import Roxas

extension AppDelegate
{
    static let openPatreonSettingsDeepLinkNotification = Notification.Name("com.rileytestut.AltStore.OpenPatreonSettingsDeepLinkNotification")
    static let importAppDeepLinkNotification = Notification.Name("com.rileytestut.AltStore.ImportAppDeepLinkNotification")
    static let addSourceDeepLinkNotification = Notification.Name("com.rileytestut.AltStore.AddSourceDeepLinkNotification")
    
    static let appBackupDidFinish = Notification.Name("com.rileytestut.AltStore.AppBackupDidFinish")
    
    static let importAppDeepLinkURLKey = "fileURL"
    static let appBackupResultKey = "result"
    static let addSourceDeepLinkURLKey = "sourceURL"
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    @available(iOS 14, *)
    private lazy var intentHandler = IntentHandler()
    
    @available(iOS 14, *)
    private lazy var viewAppIntentHandler = ViewAppIntentHandler()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        // Register default settings before doing anything else.
        UserDefaults.registerDefaults()
        
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                print("Failed to start DatabaseManager. Error:", error as Any)
            }
            else
            {
                print("Started DatabaseManager.")
            }
        }
        
        AnalyticsManager.shared.start()
        
        self.setTintColor()
        
        ServerManager.shared.startDiscovering()
        
        SecureValueTransformer.register()        
        
        if UserDefaults.standard.firstLaunch == nil
        {
            Keychain.shared.reset()
            UserDefaults.standard.firstLaunch = Date()
        }
        
        UserDefaults.standard.preferredServerID = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.serverID) as? String
        
        #if DEBUG || BETA
        UserDefaults.standard.isDebugModeEnabled = true
        #endif
        
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
        
        PatreonAPI.shared.refreshPatreonAccount()
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
    {
        return self.open(url)
    }
    
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any?
    {
        guard #available(iOS 14, *) else { return nil }
        
        switch intent
        {
        case is RefreshAllIntent: return self.intentHandler
        case is ViewAppIntent: return self.viewAppIntentHandler
        default: return nil
        }
    }
}

@available(iOS 13, *)
extension AppDelegate
{
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
    {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
    {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

private extension AppDelegate
{
    func setTintColor()
    {
        self.window?.tintColor = .altPrimary
    }
    
    func open(_ url: URL) -> Bool
    {
        if url.isFileURL
        {
            guard url.pathExtension.lowercased() == "ipa" else { return false }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: url])
            }
            
            return true
        }
        else
        {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
            guard let host = components.host?.lowercased() else { return false }
            
            switch host
            {
            case "patreon":
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
                }
                
                return true
                
            case "appbackupresponse":
                let result: Result<Void, Error>
                
                switch url.path.lowercased()
                {
                case "/success": result = .success(())
                case "/failure":
                    let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
                    guard
                        let errorDomain = queryItems["errorDomain"],
                        let errorCodeString = queryItems["errorCode"], let errorCode = Int(errorCodeString),
                        let errorDescription = queryItems["errorDescription"]
                    else { return false }
                    
                    let error = NSError(domain: errorDomain, code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorDescription])
                    result = .failure(error)
                    
                default: return false
                }
                
                NotificationCenter.default.post(name: AppDelegate.appBackupDidFinish, object: nil, userInfo: [AppDelegate.appBackupResultKey: result])
                
                return true
                
            case "install":
                let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
                guard let downloadURLString = queryItems["url"], let downloadURL = URL(string: downloadURLString) else { return false }
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: downloadURL])
                }
                
                return true
            
            case "source":
                let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
                guard let sourceURLString = queryItems["url"], let sourceURL = URL(string: sourceURLString) else { return false }
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: AppDelegate.addSourceDeepLinkNotification, object: nil, userInfo: [AppDelegate.addSourceDeepLinkURLKey: sourceURL])
                }
                
                return true
                
            default: return false
            }
        }
    }
}

extension AppDelegate
{
    private func prepareForBackgroundFetch()
    {
        // "Fetch" every hour, but then refresh only those that need to be refreshed (so we don't drain the battery).
        UIApplication.shared.setMinimumBackgroundFetchInterval(1 * 60 * 60)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (success, error) in
        }
        
        #if DEBUG
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        let tokenParts = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        
        let token = tokenParts.joined()
        print("Push Token:", token)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        self.application(application, performFetchWithCompletionHandler: completionHandler)
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler backgroundFetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        if UserDefaults.standard.isBackgroundRefreshEnabled && !UserDefaults.standard.presentedLaunchReminderNotification
        {
            let threeHours: TimeInterval = 3 * 60 * 60
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: threeHours, repeats: false)
            
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("App Refresh Tip", comment: "")
            content.body = NSLocalizedString("The more you open AltStore, the more chances it's given to refresh apps in the background.", comment: "")
            
            let request = UNNotificationRequest(identifier: "background-refresh-reminder5", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            
            UserDefaults.standard.presentedLaunchReminderNotification = true
        }
        
        BackgroundTaskManager.shared.performExtendedBackgroundTask { (taskResult, taskCompletionHandler) in
            if let error = taskResult.error
            {
                print("Error starting extended background task. Aborting.", error)
                backgroundFetchCompletionHandler(.failed)
                taskCompletionHandler()
                return
            }
            
            if !DatabaseManager.shared.isStarted
            {
                DatabaseManager.shared.start() { (error) in
                    if error != nil
                    {
                        backgroundFetchCompletionHandler(.failed)
                        taskCompletionHandler()
                    }
                    else
                    {
                        self.performBackgroundFetch { (backgroundFetchResult) in
                            backgroundFetchCompletionHandler(backgroundFetchResult)
                        } refreshAppsCompletionHandler: { (refreshAppsResult) in
                            taskCompletionHandler()
                        }
                    }
                }
            }
            else
            {
                self.performBackgroundFetch { (backgroundFetchResult) in
                    backgroundFetchCompletionHandler(backgroundFetchResult)
                } refreshAppsCompletionHandler: { (refreshAppsResult) in
                    taskCompletionHandler()
                }
            }
        }
    }
    
    func performBackgroundFetch(backgroundFetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void,
                                refreshAppsCompletionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void)
    {
        self.fetchSources { (result) in
            switch result
            {
            case .failure: backgroundFetchCompletionHandler(.failed)
            case .success: backgroundFetchCompletionHandler(.newData)
            }
            
            if !UserDefaults.standard.isBackgroundRefreshEnabled
            {
                refreshAppsCompletionHandler(.success([:]))
            }
        }
        
        guard UserDefaults.standard.isBackgroundRefreshEnabled else { return }
        
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: context)
            AppManager.shared.backgroundRefresh(installedApps, completionHandler: refreshAppsCompletionHandler)
        }
    }
}

private extension AppDelegate
{
    func fetchSources(completionHandler: @escaping (Result<Set<Source>, Error>) -> Void)
    {
        AppManager.shared.fetchSources() { (result) in
            do
            {
                let (sources, context) = try result.get()
                
                let previousUpdatesFetchRequest = InstalledApp.updatesFetchRequest() as! NSFetchRequest<NSFetchRequestResult>
                previousUpdatesFetchRequest.includesPendingChanges = false
                previousUpdatesFetchRequest.resultType = .dictionaryResultType
                previousUpdatesFetchRequest.propertiesToFetch = [#keyPath(InstalledApp.bundleIdentifier)]
                
                let previousNewsItemsFetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NSFetchRequestResult>
                previousNewsItemsFetchRequest.includesPendingChanges = false
                previousNewsItemsFetchRequest.resultType = .dictionaryResultType
                previousNewsItemsFetchRequest.propertiesToFetch = [#keyPath(NewsItem.identifier)]
                
                let previousUpdates = try context.fetch(previousUpdatesFetchRequest) as! [[String: String]]
                let previousNewsItems = try context.fetch(previousNewsItemsFetchRequest) as! [[String: String]]
                
                try context.save()
                
                let updatesFetchRequest = InstalledApp.updatesFetchRequest()
                let newsItemsFetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NewsItem>
                
                let updates = try context.fetch(updatesFetchRequest)
                let newsItems = try context.fetch(newsItemsFetchRequest)
                
                for update in updates
                {
                    guard !previousUpdates.contains(where: { $0[#keyPath(InstalledApp.bundleIdentifier)] == update.bundleIdentifier }) else { continue }
                    guard let storeApp = update.storeApp else { continue }
                    
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("New Update Available", comment: "")
                    content.body = String(format: NSLocalizedString("%@ %@ is now available for download.", comment: ""), update.name, storeApp.version)
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                
                for newsItem in newsItems
                {
                    guard !previousNewsItems.contains(where: { $0[#keyPath(NewsItem.identifier)] == newsItem.identifier }) else { continue }
                    guard !newsItem.isSilent else { continue }
                    
                    let content = UNMutableNotificationContent()
                    
                    if let app = newsItem.storeApp
                    {
                        content.title = String(format: NSLocalizedString("%@ News", comment: ""), app.name)
                    }
                    else
                    {
                        content.title = NSLocalizedString("AltStore News", comment: "")
                    }
                    
                    content.body = newsItem.title
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }

                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = updates.count
                }
                
                completionHandler(.success(sources))
            }
            catch
            {
                print("Error fetching apps:", error)
                completionHandler(.failure(error))
            }
        }
    }
}
