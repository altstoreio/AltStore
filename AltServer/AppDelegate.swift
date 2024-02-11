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
import Sparkle

extension ALTDevice: MenuDisplayable {}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let pluginManager = PluginManager()
    
    private var statusItem: NSStatusItem?
    
    private var connectedDevices = [ALTDevice]()
    
    private weak var authenticationAlert: NSAlert?
    
    @IBOutlet private var appMenu: NSMenu!
    @IBOutlet private var connectedDevicesMenu: NSMenu!
    @IBOutlet private var sideloadIPAConnectedDevicesMenu: NSMenu!
    @IBOutlet private var enableJITMenu: NSMenu!
    
    @IBOutlet private var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet private var installMailPluginMenuItem: NSMenuItem!
    @IBOutlet private var installAltStoreMenuItem: NSMenuItem!
    @IBOutlet private var sideloadAppMenuItem: NSMenuItem!
    
    private weak var authenticationAppleIDTextField: NSTextField?
    private weak var authenticationPasswordTextField: NSSecureTextField?
    
    private var connectedDevicesMenuController: MenuController<ALTDevice>!
    private var sideloadIPAConnectedDevicesMenuController: MenuController<ALTDevice>!
    private var enableJITMenuController: MenuController<ALTDevice>!
    
    private var _jitAppListMenuControllers = [AnyObject]()
    
    private var isAltPluginUpdateAvailable = false
    
    private var popoverController: NSPopover?
    private var popoverError: NSError?
    private var errorAlert: NSAlert?
    
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        UserDefaults.standard.registerDefaults()
        
        UNUserNotificationCenter.current().delegate = self
        
        ServerConnectionManager.shared.start()
        ALTDeviceManager.shared.start()
        
        #if STAGING
        SUUpdater.shared().feedURL = URL(string: "https://altstore.io/altserver/sparkle-macos-staging.xml")
        #else
        SUUpdater.shared().feedURL = URL(string: "https://altstore.io/altserver/sparkle-macos.xml")
        #endif
        
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
        self.connectedDevicesMenuController.action = { [weak self] device in
            self?.installAltStore(to: device)
        }
        
        self.sideloadIPAConnectedDevicesMenuController = MenuController<ALTDevice>(menu: self.sideloadIPAConnectedDevicesMenu, items: [])
        self.sideloadIPAConnectedDevicesMenuController.placeholder = placeholder
        self.sideloadIPAConnectedDevicesMenuController.action = { [weak self] device in
            self?.sideloadIPA(to: device)
        }
        
        self.enableJITMenuController = MenuController<ALTDevice>(menu: self.enableJITMenu, items: [])
        self.enableJITMenuController.placeholder = placeholder
        
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
    }

    func applicationWillTerminate(_ aNotification: Notification)
    {
        // Insert code here to tear down your application
    }
}

private extension AppDelegate
{
    @objc func installAltStore(to device: ALTDevice)
    {
        self.installApplication(at: nil, to: device)
    }
    
    @objc func sideloadIPA(to device: ALTDevice)
    {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedFileTypes = ["ipa"]
        openPanel.begin { (response) in
            guard let fileURL = openPanel.url, response == .OK else { return }
            self.installApplication(at: fileURL, to: device)
        }
    }
    
    func enableJIT(for app: InstalledApp, on device: ALTDevice)
    {
        Task<Void, Never> {
            do
            {
                try await JITManager.shared.enableUnsignedCodeExecution(process: .name(app.executableName), device: device)
                
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = String(format: NSLocalizedString("Successfully enabled JIT for %@.", comment: ""), app.name)
                    alert.informativeText = String(format: NSLocalizedString("JIT will remain enabled until you quit the app. You can now disconnect %@ from your computer.", comment: ""), device.name)
                    
                    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                    
                    alert.runModal()
                }
            }
            catch let error as JITError where error.code == .dependencyNotFound
            {
                var errorMessage = error.localizedDescription
                if let recoverySuggestion = error.recoverySuggestion
                {
                    errorMessage += "\n\n" + recoverySuggestion
                }
                
                await MainActor.run { [errorMessage] in
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = NSLocalizedString("Missing AltJIT Dependencies", comment: "")
                    alert.informativeText = errorMessage
                    
                    alert.addButton(withTitle: NSLocalizedString("View Instructions", comment: ""))
                    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                    
                    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn
                    {
                        let faqURL = URL(string: "https://faq.altstore.io/how-to-use-altstore/altjit")!
                        NSWorkspace.shared.open(faqURL)
                    }
                }
            }
            catch let error as NSError
            {
                await MainActor.run {
                    let localizedTitle = String(format: NSLocalizedString("JIT could not be enabled for %@.", comment: ""), app.name)
                    self.showErrorAlert(error: error.withLocalizedTitle(localizedTitle))
                }
            }
        }
    }
    
    func installApplication(at fileURL: URL?, to device: ALTDevice)
    {
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
        
        ALTDeviceManager.shared.installApplication(at: fileURL, to: device, appleID: username, password: password) { (result) in
            switch result
            {
            case .success(let application):
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Installation Succeeded", comment: "")
                content.body = String(format: NSLocalizedString("%@ was successfully installed on %@.", comment: ""), application.name, device.name)
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
                
            case .failure(OperationError.cancelled), .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                // Ignore
                break
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.showErrorAlert(error: error)
                }
            }
        }
    }
    
    func showErrorAlert(error: Error)
    {
        self.popoverError = error as NSError
        
        let nsError = error as NSError
        
        var messageComponents = [error.localizedDescription]
        if let recoverySuggestion = nsError.localizedRecoverySuggestion
        {
            messageComponents.append(recoverySuggestion)
        }
        
        let title = nsError.localizedTitle ?? NSLocalizedString("Operation Failed", comment: "")
        let message = messageComponents.joined(separator: "\n\n")
        
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("View More Details", comment: ""))
        
        if let viewMoreButton = alert.buttons.last
        {
            viewMoreButton.target = self
            viewMoreButton.action = #selector(AppDelegate.showDetailedErrorDescription)
            
            self.errorAlert = alert
        }
        
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        
        alert.runModal()
        
        self.popoverController = nil
        self.errorAlert = nil
        self.popoverError = nil
    }
    
    @objc func showDetailedErrorDescription()
    {
        guard let errorAlert, let contentView = errorAlert.window.contentView else { return }
        
        let errorDetailsViewController = NSStoryboard(name: "Main", bundle: .main).instantiateController(withIdentifier: "errorDetailsViewController") as! ErrorDetailsViewController
        errorDetailsViewController.error = self.popoverError
        
        let fittingSize = errorDetailsViewController.view.fittingSize
        errorDetailsViewController.view.frame.size = fittingSize
        
        let popoverController = NSPopover()
        popoverController.contentViewController = errorDetailsViewController
        popoverController.contentSize = fittingSize
        popoverController.behavior = .transient
        popoverController.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxX)
        self.popoverController = popoverController
    }
    
    @objc func toggleLaunchAtLogin(_ item: NSMenuItem)
    {
        LaunchAtLogin.isEnabled.toggle()
    }
    
    @IBAction private func uninstallMailPlugin(_ sender: NSMenuItem)
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
                    alert.informativeText = NSLocalizedString("Please restart Mail for changes to take effect.", comment: "")
                    alert.runModal()
                }
            }
        }
    }
    
    @IBAction private func showAboutPanel(_ sender: NSMenuItem)
    {
        let options: [NSApplication.AboutPanelOptionKey: Any]
        
        if #available(macOS 12, *)
        {
            var credits = try! AttributedString(markdown: "Thanks to [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) for their work on the iOS 17 Developer Disk format.")
            credits.font = .systemFont(ofSize: NSFont.smallSystemFontSize) // YOLO ignore Sendable warning.
            
            options = [.credits: NSAttributedString(credits)]
        }
        else
        {
            options = [:]
        }
                
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
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
        self.launchAtLoginMenuItem.action = #selector(AppDelegate.toggleLaunchAtLogin(_:))
        self.launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off

        if !self.pluginManager.isMailPluginInstalled
        {
            // Hide "Install Mail Plug-In" option now that it's not required.
            self.installMailPluginMenuItem.isHidden = true
        }
        
        // Need to re-set this every time menu appears so we can refresh device app list.
        self.enableJITMenuController.submenuHandler = { [weak self] device in
            let submenu = NSMenu(title: NSLocalizedString("Sideloaded Apps", comment: ""))
            
            guard let `self` = self else { return submenu }

            let submenuController = MenuController<InstalledApp>(menu: submenu, items: [])
            submenuController.placeholder = NSLocalizedString("Loading...", comment: "")
            submenuController.action = { [weak self] (appInfo) in
                self?.enableJIT(for: appInfo, on: device)
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
        guard menu == self.appMenu else { return }
        
        // Clearing _jitAppListMenuControllers now prevents action handler from being called.
        // self._jitAppListMenuControllers = []
        
        // Set `submenuHandler` to nil to prevent prematurely fetching installed apps in menuWillOpen(_:)
        // when assigning self.connectedDevices to `items` (which implicitly calls `submenuHandler`)
        self.enableJITMenuController.submenuHandler = nil
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
