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
import AltKit
import Roxas

private enum RefreshError: LocalizedError
{
    case noInstalledApps
    
    var errorDescription: String? {
        switch self
        {
        case .noInstalledApps: return NSLocalizedString("No active apps require refreshing.", comment: "")
        }
    }
}

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

extension AppDelegate
{
    static let openPatreonSettingsDeepLinkNotification = Notification.Name("com.rileytestut.AltStore.OpenPatreonSettingsDeepLinkNotification")
    static let importAppDeepLinkNotification = Notification.Name("com.rileytestut.AltStore.ImportAppDeepLinkNotification")
    
    static let appBackupDidFinish = Notification.Name("com.rileytestut.AltStore.AppBackupDidFinish")
    
    static let importAppDeepLinkURLKey = "fileURL"
    static let appBackupResultKey = "result"
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    private var runningApplications: Set<String>?
    private var backgroundRefreshContext: NSManagedObjectContext? // Keep context alive until finished refreshing.

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        AnalyticsManager.shared.start()
        
        self.setTintColor()
        
        ServerManager.shared.startDiscovering()
        
        UserDefaults.standard.registerDefaults()
        
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
        if UserDefaults.standard.isBackgroundRefreshEnabled
        {
            ServerManager.shared.startDiscovering()
            
            if !UserDefaults.standard.presentedLaunchReminderNotification
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
        }
        
        let refreshIdentifier = UUID().uuidString
        
        BackgroundTaskManager.shared.performExtendedBackgroundTask { (taskResult, taskCompletionHandler) in
            
            func finish(_ result: Result<[String: Result<InstalledApp, Error>], Error>)
            {
                // If finish is actually called, that means an error occured during installation.
                
                if UserDefaults.standard.isBackgroundRefreshEnabled
                {
                    ServerManager.shared.stopDiscovering()
                    self.scheduleFinishedRefreshingNotification(for: result, identifier: refreshIdentifier, delay: 0)
                }
                
                taskCompletionHandler()
                
                self.backgroundRefreshContext = nil
            }
            
            if let error = taskResult.error
            {
                print("Error starting extended background task. Aborting.", error)
                backgroundFetchCompletionHandler(.failed)
                finish(.failure(error))
                return
            }
            
            if !DatabaseManager.shared.isStarted
            {
                DatabaseManager.shared.start() { (error) in
                    if let error = error
                    {
                        backgroundFetchCompletionHandler(.failed)
                        finish(.failure(error))
                    }
                    else
                    {
                        self.refreshApps(identifier: refreshIdentifier, backgroundFetchCompletionHandler: backgroundFetchCompletionHandler, completionHandler: finish(_:))
                    }
                }
            }
            else
            {
                self.refreshApps(identifier: refreshIdentifier, backgroundFetchCompletionHandler: backgroundFetchCompletionHandler, completionHandler: finish(_:))
            }
        }
    }
}

private extension AppDelegate
{
    func refreshApps(identifier: String,
                     backgroundFetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void,
                     completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void)
    {
        var fetchSourcesResult: Result<Set<Source>, Error>?
        var serversResult: Result<Void, Error>?
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        
        AppManager.shared.fetchSources() { (result) in
            fetchSourcesResult = result
            
            do
            {
                let sources = try result.get()
                
                guard let context = sources.first?.managedObjectContext else { return }
                
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
            }
            catch
            {
                print("Error fetching apps:", error)
                
                fetchSourcesResult = .failure(error)
            }
            
            dispatchGroup.leave()
        }
        
        if UserDefaults.standard.isBackgroundRefreshEnabled
        {
            dispatchGroup.enter()
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: context)
                guard !installedApps.isEmpty else {
                    serversResult = .success(())
                    dispatchGroup.leave()
                    
                    completionHandler(.failure(RefreshError.noInstalledApps))
                    
                    return
                }
                
                self.runningApplications = []
                self.backgroundRefreshContext = context
                
                let identifiers = installedApps.compactMap { $0.bundleIdentifier }
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
                
                // Wait for three seconds to:
                // a) give us time to discover AltServers
                // b) give other processes a chance to respond to requestAppState notification
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    context.perform {
                        if ServerManager.shared.discoveredServers.isEmpty
                        {
                            serversResult = .failure(ConnectionError.serverNotFound)
                        }
                        else
                        {
                            serversResult = .success(())
                        }
                        
                        dispatchGroup.leave()
                        
                        let filteredApps = installedApps.filter { !(self.runningApplications?.contains($0.bundleIdentifier) ?? false) }
                        print("Filtered Apps to Refresh:", filteredApps.map { $0.bundleIdentifier })
                        
                        let group = AppManager.shared.refresh(filteredApps, presentingViewController: nil)
                        group.beginInstallationHandler = { (installedApp) in
                            guard installedApp.bundleIdentifier == StoreApp.altstoreAppID else { return }
                            
                            // We're starting to install AltStore, which means the app is about to quit.
                            // So, we schedule a "refresh successful" local notification to be displayed after a delay,
                            // but if the app is still running, we cancel the notification.
                            // Then, we schedule another notification and repeat the process.
                            
                            // Also since AltServer has already received the app, it can finish installing even if we're no longer running in background.
                            
                            if let error = group.context.error
                            {
                                self.scheduleFinishedRefreshingNotification(for: .failure(error), identifier: identifier)
                            }
                            else
                            {
                                var results = group.results
                                results[installedApp.bundleIdentifier] = .success(installedApp)
                                
                                self.scheduleFinishedRefreshingNotification(for: .success(results), identifier: identifier)
                            }
                        }
                        group.completionHandler = { (results) in
                            completionHandler(.success(results))
                        }
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if !UserDefaults.standard.isBackgroundRefreshEnabled
            {
                guard let fetchSourcesResult = fetchSourcesResult else {
                    backgroundFetchCompletionHandler(.failed)
                    return
                }
                
                switch fetchSourcesResult
                {
                case .failure: backgroundFetchCompletionHandler(.failed)
                case .success: backgroundFetchCompletionHandler(.newData)
                }
                
                completionHandler(.success([:]))
            }
            else
            {
                guard let fetchSourcesResult = fetchSourcesResult, let serversResult = serversResult else {
                    backgroundFetchCompletionHandler(.failed)
                    return
                }
                
                // Call completionHandler early to improve chances of refreshing in the background again.
                switch (fetchSourcesResult, serversResult)
                {
                case (.success, .success): backgroundFetchCompletionHandler(.newData)
                case (.success, .failure(ConnectionError.serverNotFound)): backgroundFetchCompletionHandler(.newData)
                case (.failure, _), (_, .failure): backgroundFetchCompletionHandler(.failed)
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
    
    func scheduleFinishedRefreshingNotification(for result: Result<[String: Result<InstalledApp, Error>], Error>, identifier: String, delay: TimeInterval = 5)
    {
        func scheduleFinishedRefreshingNotification()
        {
            self.cancelFinishedRefreshingNotification(identifier: identifier)
            
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
                
                content.title = NSLocalizedString("Refreshed Apps", comment: "")
                content.body = NSLocalizedString("All apps have been refreshed.", comment: "")
            }
            catch ConnectionError.serverNotFound
            {
                shouldPresentAlert = false
            }
            catch RefreshError.noInstalledApps
            {
                shouldPresentAlert = false
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
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)
                
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
                
                if delay > 0
                {
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        UNUserNotificationCenter.current().getPendingNotificationRequests() { (requests) in
                            // If app is still running at this point, we schedule another notification with same identifier.
                            // This prevents the currently scheduled notification from displaying, and starts another countdown timer.
                            // First though, make sure there _is_ still a pending request, otherwise it's been cancelled
                            // and we should stop polling.
                            guard requests.contains(where: { $0.identifier == identifier }) else { return }
                            
                            scheduleFinishedRefreshingNotification()
                        }
                    }
                }
            }
        }
        
        scheduleFinishedRefreshingNotification()
        
        // Perform synchronously to ensure app doesn't quit before we've finishing saving to disk.
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.performAndWait {
            _ = RefreshAttempt(identifier: identifier, result: result, context: context)
            
            do { try context.save() }
            catch { print("Failed to save refresh attempt.", error) }
        }
    }
    
    func cancelFinishedRefreshingNotification(identifier: String)
    {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
