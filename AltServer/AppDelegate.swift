//
//  AppDelegate.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa
import UserNotifications

import AltSign

import LaunchAtLogin

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let pluginManager = PluginManager()
    
    private var statusItem: NSStatusItem?
    
    private var connectedDevices = [ALTDevice]()
    
    private weak var authenticationAlert: NSAlert?
    
    @IBOutlet private var appMenu: NSMenu!
    @IBOutlet private var connectedDevicesMenu: NSMenu!
    @IBOutlet private var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet private var installMailPluginMenuItem: NSMenuItem!
    
    private weak var authenticationAppleIDTextField: NSTextField?
    private weak var authenticationPasswordTextField: NSSecureTextField?
    
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        UserDefaults.standard.registerDefaults()
        
        UNUserNotificationCenter.current().delegate = self
        
        ServerConnectionManager.shared.start()
        ALTDeviceManager.shared.start()
        
        let item = NSStatusBar.system.statusItem(withLength: -1)
        item.menu = self.appMenu
        item.button?.image = NSImage(named: "MenuBarIcon") 
        self.statusItem = item
        
        self.appMenu.delegate = self
        self.connectedDevicesMenu.delegate = self
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (success, error) in
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
        
        if self.pluginManager.isUpdateAvailable
        {
            self.installMailPlugin()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification)
    {
        // Insert code here to tear down your application
    }
}

private extension AppDelegate
{
    @objc func installAltStore(_ item: NSMenuItem)
    {
        guard case let index = self.connectedDevicesMenu.index(of: item), index != -1 else { return }
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Please enter your Apple ID and password.", comment: "")
        alert.informativeText = NSLocalizedString("Your Apple ID and password are not saved and are only sent to Apple for authentication.", comment: "")
        
        let textFieldSize = NSSize(width: 300, height: 22)
        
        let appleIDTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height))
        appleIDTextField.delegate = self
        appleIDTextField.translatesAutoresizingMaskIntoConstraints = false
        appleIDTextField.placeholderString = NSLocalizedString("Apple ID", comment: "")
        alert.window.initialFirstResponder = appleIDTextField
        self.authenticationAppleIDTextField = appleIDTextField
        
        let passwordTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height))
        passwordTextField.delegate = self
        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        passwordTextField.placeholderString = NSLocalizedString("Password", comment: "")
        self.authenticationPasswordTextField = passwordTextField
        
        appleIDTextField.nextKeyView = passwordTextField
        
        let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height * 2))
        stackView.orientation = .vertical
        stackView.distribution = .equalSpacing
        stackView.spacing = 0
        stackView.addArrangedSubview(appleIDTextField)
        stackView.addArrangedSubview(passwordTextField)
        alert.accessoryView = stackView
        
        alert.addButton(withTitle: NSLocalizedString("Install", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        
        self.authenticationAlert = alert
        self.validate()
        
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        let username = appleIDTextField.stringValue
        let password = passwordTextField.stringValue
        
        let device = self.connectedDevices[index]
        
        func install()
        {
            ALTDeviceManager.shared.installAltStore(to: device, appleID: username, password: password) { (result) in
                switch result
                {
                case .success:
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("Installation Succeeded", comment: "")
                    content.body = String(format: NSLocalizedString("AltStore was successfully installed on %@.", comment: ""), device.name)
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                    
                case .failure(InstallError.cancelled), .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                    // Ignore
                    break
                    
                case .failure(let error as NSError):
                    
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString("Installation Failed", comment: "")
                    
                    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error
                    {
                        alert.informativeText = underlyingError.localizedDescription
                    }
                    else if let recoverySuggestion = error.localizedRecoverySuggestion
                    {
                        alert.informativeText = error.localizedDescription + "\n\n" + recoverySuggestion
                    }
                    else
                    {
                        alert.informativeText = error.localizedDescription
                    }
                    
                    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

                    alert.runModal()
                }
            }
        }
        
        if !self.pluginManager.isMailPluginInstalled || self.pluginManager.isUpdateAvailable
        {
            self.installMailPlugin { (result) in
                switch result
                {
                case .failure: break
                case .success: install()
                }
            }
        }
        else
        {
            install()
        }
    }
    
    @objc func toggleLaunchAtLogin(_ item: NSMenuItem)
    {
        LaunchAtLogin.isEnabled.toggle()
    }
    
    @objc func handleInstallMailPluginMenuItem(_ item: NSMenuItem)
    {
        if !self.pluginManager.isMailPluginInstalled || self.pluginManager.isUpdateAvailable
        {
            self.installMailPlugin()
        }
        else
        {
            self.uninstallMailPlugin()
        }
    }
    
    private func installMailPlugin(completion: ((Result<Void, Error>) -> Void)? = nil)
    {
        self.pluginManager.installMailPlugin { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(PluginError.cancelled): break
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Failed to Install Mail Plug-in", comment: "")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    
                case .success:
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Mail Plug-in Installed", comment: "")
                    alert.informativeText = NSLocalizedString("Please restart Mail and enable AltPlugin in Mail's Preferences. Mail must be running when installing or refreshing apps with AltServer.", comment: "")
                    alert.runModal()
                }
                
                completion?(result)
            }
        }
    }
    
    private func uninstallMailPlugin()
    {
        self.pluginManager.uninstallMailPlugin { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(PluginError.cancelled): break
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Failed to Uninstall Mail Plug-in", comment: "")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    
                case .success:
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Mail Plug-in Uninstalled", comment: "")
                    alert.informativeText = NSLocalizedString("Please restart Mail for changes to take effect. You will not be able to use AltServer until the plug-in is reinstalled.", comment: "")
                    alert.runModal()
                }
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate
{
    func menuWillOpen(_ menu: NSMenu)
    {
        guard menu == self.appMenu else { return }

        self.connectedDevices = ALTDeviceManager.shared.connectedDevices

        self.launchAtLoginMenuItem.target = self
        self.launchAtLoginMenuItem.action = #selector(AppDelegate.toggleLaunchAtLogin(_:))
        self.launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off

        if self.pluginManager.isUpdateAvailable
        {
            self.installMailPluginMenuItem.title = NSLocalizedString("Update Mail Plug-in", comment: "")
        }
        else if self.pluginManager.isMailPluginInstalled
        {
            self.installMailPluginMenuItem.title = NSLocalizedString("Uninstall Mail Plug-in", comment: "")
        }
        else
        {
            self.installMailPluginMenuItem.title = NSLocalizedString("Install Mail Plug-in", comment: "")
        }
        self.installMailPluginMenuItem.target = self
        self.installMailPluginMenuItem.action = #selector(AppDelegate.handleInstallMailPluginMenuItem(_:))
    }

    func numberOfItems(in menu: NSMenu) -> Int
    {
        guard menu == self.connectedDevicesMenu else { return -1 }
        
        return self.connectedDevices.isEmpty ? 1 : self.connectedDevices.count
    }
    
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool
    {
        guard menu == self.connectedDevicesMenu else { return false }
        
        if self.connectedDevices.isEmpty
        {
            item.title = NSLocalizedString("No Connected Devices", comment: "")
            item.isEnabled = false
            item.target = nil
            item.action = nil
        }
        else
        {
            let device = self.connectedDevices[index]
            item.title = device.name
            item.isEnabled = true
            item.target = self
            item.action = #selector(AppDelegate.installAltStore)
            item.tag = index
        }
        
        return true
    }
}

extension AppDelegate: NSTextFieldDelegate
{
    func controlTextDidChange(_ obj: Notification)
    {
        self.validate()
    }
    
    func controlTextDidEndEditing(_ obj: Notification)
    {
        self.validate()
    }
    
    private func validate()
    {
        guard
            let appleID = self.authenticationAppleIDTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            let password = self.authenticationPasswordTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        
        if appleID.isEmpty || password.isEmpty
        {
            self.authenticationAlert?.buttons.first?.isEnabled = false
        }
        else
        {
            self.authenticationAlert?.buttons.first?.isEnabled = true
        }
        
        self.authenticationAlert?.layout()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate
{
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.alert, .sound, .badge])
    }
}
