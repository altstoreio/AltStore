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
import STPrivilegedTask

private let pluginDirectoryURL = URL(fileURLWithPath: "/Library/Mail/Bundles", isDirectory: true)
private let pluginURL = pluginDirectoryURL.appendingPathComponent("AltPlugin.mailbundle")

enum PluginError: LocalizedError
{
    case cancelled
    case unknown
    case taskError(String)
    case taskErrorCode(Int)
    
    var errorDescription: String? {
        switch self
        {
        case .cancelled: return NSLocalizedString("Mail plug-in installation was cancelled.", comment: "")
        case .unknown: return NSLocalizedString("Failed to install Mail plug-in.", comment: "")
        case .taskError(let output): return output
        case .taskErrorCode(let errorCode): return String(format: NSLocalizedString("There was an error installing the Mail plug-in. (Error Code: %@)", comment: ""), NSNumber(value: errorCode))
        }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    
    private var connectedDevices = [ALTDevice]()
    
    private weak var authenticationAlert: NSAlert?
    
    @IBOutlet private var appMenu: NSMenu!
    @IBOutlet private var connectedDevicesMenu: NSMenu!
    @IBOutlet private var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet private var installMailPluginMenuItem: NSMenuItem!
    
    private weak var authenticationAppleIDTextField: NSTextField?
    private weak var authenticationPasswordTextField: NSSecureTextField?
    
    private var isMailPluginInstalled: Bool {
        let isMailPluginInstalled = FileManager.default.fileExists(atPath: pluginURL.path)
        return isMailPluginInstalled
    }
    
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
        
        if !self.isMailPluginInstalled
        {
            self.installMailPlugin { (result) in
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
                        
                        install()
                    }
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
        if self.isMailPluginInstalled
        {
            self.uninstallMailPlugin { (result) in
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
        else
        {
            self.installMailPlugin { (result) in
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
                }
            }
        }
    }
    
    func installMailPlugin(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        do
        {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Install Mail Plug-in", comment: "")
            alert.informativeText = NSLocalizedString("AltServer requires a Mail plug-in in order to retrieve necessary information about your Apple ID. Would you like to install it now?", comment: "")
            
            alert.addButton(withTitle: NSLocalizedString("Install Plug-in", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
            
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { throw PluginError.cancelled }
            
            self.downloadPlugin { (result) in
                do
                {
                    let fileURL = try result.get()
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    
                    // Ensure plug-in directory exists.
                    let authorization = try self.runAndKeepAuthorization("mkdir", arguments: ["-p", pluginDirectoryURL.path])
                    
                    // Unzip AltPlugin to plug-ins directory.
                    try self.runAndKeepAuthorization("unzip", arguments: ["-o", fileURL.path, "-d", pluginDirectoryURL.path], authorization: authorization)
                    guard self.isMailPluginInstalled else { throw PluginError.unknown }
                    
                    // Enable Mail plug-in preferences.
                    try self.run("defaults", arguments: ["write", "/Library/Preferences/com.apple.mail", "EnableBundles", "-bool", "YES"], authorization: authorization)
                    
                    print("Finished installing Mail plug-in!")
                    
                    completionHandler(.success(()))
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
        catch
        {
            completionHandler(.failure(PluginError.cancelled))
        }
    }
    
    func downloadPlugin(completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        let pluginURL = URL(string: "https://f000.backblazeb2.com/file/altstore/altserver/altplugin/1_0.zip")!
        
        let downloadTask = URLSession.shared.downloadTask(with: pluginURL) { (fileURL, response, error) in
            if let fileURL = fileURL
            {
                print("Downloaded plugin to URL:", fileURL)
                completionHandler(.success(fileURL))
            }
            else
            {
                completionHandler(.failure(error ?? PluginError.unknown))
            }
        }
        
        downloadTask.resume()
    }
    
    func uninstallMailPlugin(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Uninstall Mail Plug-in", comment: "")
        alert.informativeText = NSLocalizedString("Are you sure you want to uninstall the AltServer Mail plug-in? You will no longer be able to install or refresh apps with AltStore.", comment: "")
        
        alert.addButton(withTitle: NSLocalizedString("Uninstall Plug-in", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return completionHandler(.failure(PluginError.cancelled)) }
        
        DispatchQueue.global().async {
            do
            {
                if FileManager.default.fileExists(atPath: pluginURL.path)
                {
                    // Delete Mail plug-in from privileged directory.
                    try self.run("rm", arguments: ["-rf", pluginURL.path])
                }
                
                completionHandler(.success(()))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
}

private extension AppDelegate
{
    func run(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil) throws
    {
        _ = try self._run(program, arguments: arguments, authorization: authorization, freeAuthorization: true)
    }
    
    @discardableResult
    func runAndKeepAuthorization(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil) throws -> AuthorizationRef
    {
        return try self._run(program, arguments: arguments, authorization: authorization, freeAuthorization: false)
    }
    
    func _run(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil, freeAuthorization: Bool) throws -> AuthorizationRef
    {
        var launchPath = "/usr/bin/" + program
        if !FileManager.default.fileExists(atPath: launchPath)
        {
            launchPath = "/bin/" + program
        }
        
        print("Running program:", launchPath)
        
        let task = STPrivilegedTask()
        task.launchPath = launchPath
        task.arguments = arguments
        task.freeAuthorizationWhenDone = freeAuthorization
        
        let errorCode: OSStatus
        
        if let authorization = authorization
        {
            errorCode = task.launch(withAuthorization: authorization)
        }
        else
        {
            errorCode = task.launch()
        }
        
        guard errorCode == 0 else { throw PluginError.taskErrorCode(Int(errorCode)) }
        
        task.waitUntilExit()
        
        print("Exit code:", task.terminationStatus)
        
        guard task.terminationStatus == 0 else {
            let outputData = task.outputFileHandle.readDataToEndOfFile()
            
            if let outputString = String(data: outputData, encoding: .utf8), !outputString.isEmpty
            {
                throw PluginError.taskError(outputString)
            }
            
            throw PluginError.taskErrorCode(Int(task.terminationStatus))
        }
        
        guard let authorization = task.authorization else { throw PluginError.unknown }
        return authorization
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

        if self.isMailPluginInstalled
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
