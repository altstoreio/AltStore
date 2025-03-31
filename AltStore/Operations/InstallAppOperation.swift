//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import Network

import AltStoreCore
import AltSign
import Roxas
import minimuxer

@objc(InstallAppOperation)
final class InstallAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    private var didCleanUp = false
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let certificate = self.context.certificate,
            let resignedApp = self.context.resignedApp,
            let provisioningProfiles = self.context.provisioningProfiles
        else {
            return self.finish(.failure(OperationError.invalidParameters("InstallAppOperation.main: self.context.certificate or self.context.resignedApp or self.context.provisioningProfiles is nil")))
        }

        @Managed var appVersion = self.context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        backgroundContext.perform {
            
            
            /* App */
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: resignedApp,
                                            originalBundleIdentifier: self.context.bundleIdentifier,
                                            certificateSerialNumber: certificate.serialNumber,
                                            storeBuildVersion: storeBuildVersion,
                                            context: backgroundContext)
            }
            
            installedApp.update(resignedApp: resignedApp, certificateSerialNumber: certificate.serialNumber, storeBuildVersion: storeBuildVersion)
            installedApp.needsResign = false
            
            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext)
            {
                installedApp.team = team
            }
            
            /* App Extensions */
            var installedExtensions = Set<InstalledExtension>()
            
            if
                let bundle = Bundle(url: resignedApp.fileURL),
                let directory = bundle.builtInPlugInsURL,
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            {
                for case let fileURL as URL in enumerator
                {
                    guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                    guard let appExtension = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }
                    
                    let parentBundleID = self.context.bundleIdentifier
                    let resignedParentBundleID = resignedApp.bundleIdentifier
                    
                    let resignedBundleID = appExtension.bundleIdentifier
                    let originalBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: parentBundleID)
                    
                    print("`parentBundleID`: \(parentBundleID)")
                    print("`resignedParentBundleID`: \(resignedParentBundleID)")
                    print("`resignedBundleID`: \(resignedBundleID)")
                    print("`originalBundleID`: \(originalBundleID)")
                    
                    let installedExtension: InstalledExtension
                    
                    if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == originalBundleID })
                    {
                        installedExtension = appExtension
                    }
                    else
                    {
                        installedExtension = InstalledExtension(resignedAppExtension: appExtension, originalBundleIdentifier: originalBundleID, context: backgroundContext)
                    }
                    
                    installedExtension.update(resignedAppExtension: appExtension)
                    
                    installedExtensions.insert(installedExtension)
                }
            }
            
            installedApp.appExtensions = installedExtensions

            // Remove stale "PlugIns" (Extensions) from currently installed App
            if let installedAppExns = ALTApplication(fileURL: installedApp.fileURL)?.appExtensions {
                let currentAppExns = Set(installedApp.appExtensions).map{ $0.bundleIdentifier }
                let staleAppExns = installedAppExns.filter{ !currentAppExns.contains($0.bundleIdentifier) }
                
                for staleAppExn in staleAppExns {
                    do {
                        try FileManager.default.removeItem(at: staleAppExn.fileURL)
                        print("InstallAppOperation.appExtensions: removed stale app-extension: \(staleAppExn.fileURL)")
                    } catch {
                        print("InstallAppOperation.appExtensions processing error Error: \(error)")
                    }
                }
            }
            
            
            self.context.beginInstallationHandler?(installedApp)
            
            // Temporary directory and resigned .ipa no longer needed, so delete them now to ensure AltStore doesn't quit before we get the chance to.
            self.cleanUp()
            
            if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit, provisioningProfiles.contains(where: { $1.isFreeProvisioningProfile == true })
            {
                // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
                
                let fetchRequest = InstalledApp.activeAppsFetchRequest()
                fetchRequest.includesPendingChanges = false
                
                var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
                if !activeApps.contains(installedApp)
                {
                    let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
                    let availableActiveApps = max(sideloadedAppsLimit - activeAppsCount, 0)
                    if installedApp.requiredActiveSlots <= availableActiveApps
                    {
                        // This app has not been explicitly activated, but there are enough slots available,
                        // so implicitly activate it.
                        installedApp.isActive = true
                        activeApps.append(installedApp)
                    }
                    else
                    {
                        installedApp.isActive = false
                    }
                }
            }
            else
            {
                installedApp.isActive = true
            }
            
            var installing = true
            if installedApp.storeApp?.bundleIdentifier.range(of: Bundle.Info.appbundleIdentifier) != nil {
                // Reinstalling ourself will hang until we leave the app, so we need to exit it without force closing
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if UIApplication.shared.applicationState != .active {
                        print("We are not in the foreground, let's not do anything")
                        return
                    }
                    if !installing {
                        print("Installing finished")
                        return
                    }
                    print("We are still installing after 3 seconds")
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        switch (settings.authorizationStatus) {
                        case .authorized, .ephemeral, .provisional:
                            print("Notifications are enabled")

                            let content = UNMutableNotificationContent()
                            content.title = "Refreshing..."
                            content.body = "SideStore will automatically move to the homescreen to finish refreshing!"
                            let notification = UNNotificationRequest(identifier: Bundle.Info.appbundleIdentifier + ".FinishRefreshNotification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
                            UNUserNotificationCenter.current().add(notification)
                            break
                        default:
                            print("Notifications are not enabled")

                            let alert = UIAlertController(title: "Finish Refresh", message: "Please reopen SideStore after the process is finished.To finish refreshing, SideStore must be moved to the background. To do this, you can either go to the Home Screen manually or by hitting Continue. Please reopen SideStore after doing this.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { _ in
                                print("Going home")
                                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                            }))

                            DispatchQueue.main.async {
                                let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first
                                if var topController = keyWindow?.rootViewController {
                                    while let presentedViewController = topController.presentedViewController {
                                        topController = presentedViewController
                                    }
                                    topController.present(alert, animated: true)
                                } else {
                                    print("No key window? Let's just go home")
                                }
                            }
                        }
                    }
                    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                }
            }
            
            do {
                UIApplication.shared.open("shortcuts://run-shortcut?name=TurnOffData", completionHandler: nil)
                try install_ipa(installedApp.bundleIdentifier)
                installing = false
                installedApp.refreshedDate = Date()
                self.finish(.success(installedApp))
            } catch let error {
                installing = false
                self.finish(.failure(error))
            }
        }
    }
    
    override func finish(_ result: Result<InstalledApp, Error>)
    {
        self.cleanUp()
        
        // Only remove refreshed IPA when finished.
        if let app = self.context.app
        {
            let fileURL = InstalledApp.refreshedIPAURL(for: app)
            
            do
            {
                if(FileManager.default.fileExists(atPath: fileURL.path)){
                    try FileManager.default.removeItem(at: fileURL)
                    print("Removed refreshed IPA")
                }
            }
            catch
            {
                print("Failed to remove refreshed .ipa: \(error)")
            }
        }
        
        super.finish(result)
    }
}

private extension InstallAppOperation
{
    func cleanUp()
    {
        guard !self.didCleanUp else { return }
        self.didCleanUp = true
        
        do
        {
            try FileManager.default.removeItem(at: self.context.temporaryDirectory)
        }
        catch
        {
            print("Failed to remove temporary directory.", error)
        }
    }
}
