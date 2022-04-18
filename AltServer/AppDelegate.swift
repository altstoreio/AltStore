//
//  AppDelegate.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa
import UserNotifications
import LaunchAtLogin

extension ALTDevice: MenuDisplayable {}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    
    private var connectedDevices = [ALTDevice]()
    
    @IBOutlet private var appMenu: NSMenu!
    @IBOutlet private var connectedDevicesMenu: NSMenu!

    @IBOutlet private var installAltStoreMenuItem: NSMenuItem!
    @IBOutlet private var sideloadAppMenuItem: NSMenuItem!
    @IBOutlet private var sideloadIPAConnectedDevicesMenu: NSMenu!
    @IBOutlet private var enableJITMenu: NSMenu!
    
    @IBOutlet private var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet private var installMailPluginMenuItem: NSMenuItem!
    @IBOutlet private var logOutMenuItem: NSMenuItem!

    private var connectedDevicesMenuController: MenuController<ALTDevice>!
    private var sideloadIPAConnectedDevicesMenuController: MenuController<ALTDevice>!
    private var enableJITMenuController: MenuController<ALTDevice>!
    
    private var _jitAppListMenuControllers = [AnyObject]()
    
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        UserDefaults.standard.registerDefaults()
        
        UNUserNotificationCenter.current().delegate = self
        
        ServerConnectionManager.shared.start()
        ALTDeviceManager.shared.start()

        setupMenu()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (success, _) in
            guard success else { return }
            
            if !UserDefaults.standard.didPresentInitialNotification
            {
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("AltServer Running", comment: "")
                content.body = NSLocalizedString("AltServer runs in the background as a menu bar app listening for AltStore.", comment: "")
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
                
                UserDefaults.standard.didPresentInitialNotification = true
            }
        }

        if PluginManager.shared.isUpdateAvailable {
            PluginManager.shared.installMailPlugin(completionHandler: { _ in })
        }
    }

    func applicationWillTerminate(_ aNotification: Notification)
    {
        // Insert code here to tear down your application
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: -1)
        item.menu = self.appMenu
        item.button?.image = NSImage(named: "MenuBarIcon")
        self.statusItem = item

        self.appMenu.delegate = self

        self.sideloadAppMenuItem.keyEquivalentModifierMask = .option
        self.sideloadAppMenuItem.isAlternate = true

        let placeholder = NSLocalizedString("No Connected Devices", comment: "")

        self.connectedDevicesMenuController = MenuController<ALTDevice>(menu: self.connectedDevicesMenu, items: [])
        self.connectedDevicesMenuController.placeholder = placeholder
        self.connectedDevicesMenuController.action = { device in
            InstallationManager.shared.installAltStore(to: device)
        }

        self.sideloadIPAConnectedDevicesMenuController = MenuController<ALTDevice>(menu: self.sideloadIPAConnectedDevicesMenu, items: [])
        self.sideloadIPAConnectedDevicesMenuController.placeholder = placeholder
        self.sideloadIPAConnectedDevicesMenuController.action = { device in
            InstallationManager.shared.sideloadIPA(to: device)
        }

        self.enableJITMenuController = MenuController<ALTDevice>(menu: self.enableJITMenu, items: [])
        self.enableJITMenuController.placeholder = placeholder
    }
}

extension AppDelegate: NSMenuDelegate
{
    func menuWillOpen(_ menu: NSMenu)
    {
        guard menu == self.appMenu else { return }
        
        // Clear any cached _jitAppListMenuControllers.
        self._jitAppListMenuControllers.removeAll()

        self.connectedDevices = ALTDeviceManager.shared.availableDevices
        
        self.connectedDevicesMenuController.items = self.connectedDevices
        self.sideloadIPAConnectedDevicesMenuController.items = self.connectedDevices
        self.enableJITMenuController.items = self.connectedDevices

        self.launchAtLoginMenuItem.target = self
        self.launchAtLoginMenuItem.action = #selector(AppDelegate.handleToggleLaunchAtLoginItem(_:))
        self.launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off

        if PluginManager.shared.isUpdateAvailable {
            self.installMailPluginMenuItem.title = NSLocalizedString("Update Mail Plug-in", comment: "")
        } else if PluginManager.shared.isMailPluginInstalled {
            self.installMailPluginMenuItem.title = NSLocalizedString("Uninstall Mail Plug-in", comment: "")
        }
        else
        {
            self.installMailPluginMenuItem.title = NSLocalizedString("Install Mail Plug-in", comment: "")
        }
        self.installMailPluginMenuItem.target = self
        self.installMailPluginMenuItem.action = #selector(AppDelegate.handleInstallMailPluginMenuItem(_:))
        
        if let appleIDEmailAddress = Keychain.shared.appleIDEmailAddress {
            self.logOutMenuItem.title = "Log out (\(appleIDEmailAddress))"
            self.logOutMenuItem.target = self
            self.logOutMenuItem.action = #selector(AppDelegate.handleLogOutMenuItem(_:))
        } else {
            self.logOutMenuItem.title = "Not logged in"
            self.logOutMenuItem.isEnabled = false
        }

        // Need to re-set this every time menu appears so we can refresh device app list.
        self.enableJITMenuController.submenuHandler = { [weak self] device in
            let submenu = NSMenu(title: NSLocalizedString("Sideloaded Apps", comment: ""))
            
            guard let `self` = self else { return submenu }

            let submenuController = MenuController<InstalledApp>(menu: submenu, items: [])
            submenuController.placeholder = NSLocalizedString("Loading...", comment: "")
            submenuController.action = { appInfo in
                InstallationManager.shared.enableJIT(for: appInfo, on: device)
            }
            
            // Keep strong reference
            self._jitAppListMenuControllers.append(submenuController)

            ALTDeviceManager.shared.fetchInstalledApps(on: device) { (installedApps, error) in
                DispatchQueue.main.async {
                    guard let installedApps = installedApps else {
                        print("Failed to fetch installed apps from \(device).", error!)
                        submenuController.placeholder = error?.localizedDescription
                        return
                    }
                    
                    print("Fetched \(installedApps.count) apps for \(device).")
                    
                    let sortedApps = installedApps.sorted { (app1, app2) in
                        if app1.name == app2.name
                        {
                            return app1.bundleIdentifier < app2.bundleIdentifier
                        }
                        else
                        {
                            return app1.name < app2.name
                        }
                    }
                    
                    submenuController.items = sortedApps
                    
                    if submenuController.items.isEmpty
                    {
                        submenuController.placeholder = NSLocalizedString("No Sideloaded Apps", comment: "")
                    }
                }
            }

            return submenu
        }
    }
    
    func menuDidClose(_ menu: NSMenu)
    {
        // Clearing _jitAppListMenuControllers now prevents action handler from being called.
        // self._jitAppListMenuControllers = []
    }
    
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?)
    {
        guard menu == self.appMenu else { return }
        
        // The submenu won't update correctly if the user holds/releases
        // the Option key while the submenu is visible.
        // Workaround: temporarily set submenu to nil to dismiss it,
        // which will then cause the correct submenu to appear.
        
        let previousItem: NSMenuItem
        switch item
        {
        case self.sideloadAppMenuItem: previousItem = self.installAltStoreMenuItem
        case self.installAltStoreMenuItem: previousItem = self.sideloadAppMenuItem
        default: return
        }

        let submenu = previousItem.submenu
        previousItem.submenu = nil
        previousItem.submenu = submenu
    }
}

extension AppDelegate {
    @objc func handleToggleLaunchAtLoginItem(_ item: NSMenuItem) {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc func handleInstallMailPluginMenuItem(_ item: NSMenuItem) {
        if !PluginManager.shared.isMailPluginInstalled || PluginManager.shared.isUpdateAvailable {
            PluginManager.shared.installMailPlugin(completionHandler: { _ in })
        } else {
            PluginManager.shared.uninstallMailPlugin(completionHandler: { _ in })
        }
    }

    @objc func handleLogOutMenuItem(_ item: NSMenuItem) {
        Keychain.shared.reset()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.sound, .badge])
    }
}
