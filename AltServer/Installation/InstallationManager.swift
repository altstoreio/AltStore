//
//  InstallationManager.swift
//  AltServer
//
//  Created by royal on 09/01/2022.
//

import Foundation
import Cocoa
import UserNotifications
import UniformTypeIdentifiers
import AltSign
import LaunchAtLogin

final class InstallationManager: NSObject {
    static let shared = InstallationManager()

    #if STAGING
    private let altstoreAppURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore.ipa")!
    #elseif BETA
    private let altstoreAppURL = URL(string: "https://cdn.altstore.io/file/altstore/altstore-beta.ipa")!
    #else
    private let altstoreAppURL = URL(string: "https://cdn.altstore.io/file/altstore/altstore.ipa")!
    #endif

    private weak var authenticationAlert: NSAlert?
    private weak var authenticationAppleIDTextField: NSTextField?
    private weak var authenticationPasswordTextField: NSSecureTextField?

    private weak var progressViewWindowController: NSWindowController?

    func enableJIT(for app: InstalledApp, on device: ALTDevice) {
        func finish(_ result: Result<Void, Error>) {
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.showErrorAlert(error: error, localizedFailure: String(format: NSLocalizedString("JIT compilation could not be enabled for %@.", comment: ""), app.name))

                case .success:
                    let alert = NSAlert()
                    alert.messageText = String(format: NSLocalizedString("Successfully enabled JIT for %@.", comment: ""), app.name)
                    alert.informativeText = String(format: NSLocalizedString("JIT will remain enabled until you quit the app. You can now disconnect %@ from your computer.", comment: ""), device.name)
                    alert.runModal()
                }
            }
        }

        ALTDeviceManager.shared.prepare(device) { (result) in
            switch result {
            case .failure(let error as NSError): return finish(.failure(error))
            case .success:
                ALTDeviceManager.shared.startDebugConnection(to: device) { (connection, error) in
                    guard let connection = connection else {
                        return finish(.failure(error! as NSError))
                    }

                    connection.enableUnsignedCodeExecutionForProcess(withName: app.executableName) { (success, error) in
                        guard success else {
                            return finish(.failure(error!))
                        }

                        finish(.success(()))
                    }
                }
            }
        }
    }

    func installApplication(at url: URL, to device: ALTDevice) {
        NSLog("Installing %@ to %@ (%@)", url.absoluteString, device.name, device.identifier)

        var username = Keychain.shared.appleIDEmailAddress
        var password = Keychain.shared.appleIDPassword

        if username == nil || password == nil {
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

            username = appleIDTextField.stringValue
            password = passwordTextField.stringValue
        }

        func install() {
            Keychain.shared.appleIDEmailAddress = username
            Keychain.shared.appleIDPassword = password

            setupProgressView(fileURL: url, device: device)

            let userInfo = [
                "status": InstallationStatus.initializing.rawValue
            ]
            NotificationCenter.default.post(name: .installationStatusNotification, object: nil, userInfo: userInfo)

            ALTDeviceManager.shared.installApplication(at: url, to: device, appleID: username ?? "", password: password ?? "") { (result) in
                switch result {
                    case .success(let application):
                        let userInfo: [String: Any] = [
                            "status": InstallationStatus.finished.rawValue,
                            "success": true
                        ]
                        NotificationCenter.default.post(name: .installationStatusNotification, object: nil, userInfo: userInfo)

                        let content = UNMutableNotificationContent()
                        content.title = NSLocalizedString("Installation Succeeded", comment: "")
                        content.body = NSLocalizedString("\(application.name) was successfully installed on \(device.name).", comment: "")

                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    case .failure(InstallError.cancelled), .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                        // Ignore
                        break

                    case .failure(let error):
                        let userInfo: [String: Any] = [
                            "status": InstallationStatus.finished.rawValue,
                            "success": false,
                            "error": error
                        ]
                        NotificationCenter.default.post(name: .installationStatusNotification, object: nil, userInfo: userInfo)
                        self.showErrorAlert(error: error, localizedFailure: String(format: NSLocalizedString("Could not install app to %@.", comment: ""), device.name))
                }
            }
        }

        if !PluginManager.shared.isMailPluginInstalled || PluginManager.shared.isUpdateAvailable {
            AnisetteDataManager.shared.isXPCAvailable { (isAvailable) in
                if isAvailable {
                    // XPC service is available, so we don't need to install/update Mail plug-in.
                    // Users can still manually do so from the AltServer menu.
                    install()
                } else {
                    DispatchQueue.main.async {
                        PluginManager.shared.installMailPlugin { (result) in
                            switch result {
                            case .failure: break
                            case .success: install()
                            }
                        }
                    }
                }
            }
        } else {
            install()
        }
    }

    private func setupProgressView(fileURL: URL, device: ALTDevice) {
        guard let windowController = NSStoryboard(name: "InstallationProgressView", bundle: nil).instantiateInitialController() as? NSWindowController else { return }
        windowController.window?.styleMask = [.utilityWindow, .titled, .fullSizeContentView, .miniaturizable]

        if let view = windowController.contentViewController as? InstallationProgressViewController {
            view.setup(fileURL: fileURL, device: device, onFinish: {
                if #available(macOS 11, *) {
                    windowController.window?.subtitle = "Finished installing to \(device.name)!"
                }
                windowController.window?.styleMask.insert(.closable)
            })
        }

        if #available(macOS 11, *) {
            windowController.window?.subtitle = "Installing to \(device.name)..."
        }

        windowController.showWindow(self)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

        self.progressViewWindowController = windowController
    }

    private func showErrorAlert(error: Error, localizedFailure: String) {
        let nsError = error as NSError

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizedFailure

        var messageComponents = [String]()

        let separator: String
        switch error {
        case ALTServerError.maximumFreeAppLimitReached: separator = "\n\n"
        default: separator = " "
        }

        if let errorFailure = nsError.localizedFailure {
            if let failureReason = nsError.localizedFailureReason {
                if nsError.localizedDescription.starts(with: errorFailure) {
                    alert.messageText = errorFailure
                    messageComponents.append(failureReason)
                } else {
                    alert.messageText = errorFailure
                    messageComponents.append(nsError.localizedDescription)
                }
            } else {
                // No failure reason given.

                if nsError.localizedDescription.starts(with: errorFailure) {
                    // No need to duplicate errorFailure in both title and message.
                    alert.messageText = localizedFailure
                    messageComponents.append(nsError.localizedDescription)
                } else {
                    alert.messageText = errorFailure
                    messageComponents.append(nsError.localizedDescription)
                }
            }
        } else {
            alert.messageText = localizedFailure
            messageComponents.append(nsError.localizedDescription)
        }

        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
            messageComponents.append(recoverySuggestion)
        }

        let informativeText = messageComponents.joined(separator: separator)
        alert.informativeText = informativeText

        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

        alert.runModal()
    }

    @objc func installAltStore(to device: ALTDevice) {
        self.installApplication(at: altstoreAppURL, to: device)
    }

    @objc func sideloadIPA(to device: ALTDevice) {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if #available(macOS 11, *) {
            openPanel.allowedContentTypes = [UTType(filenameExtension: "ipa")!]
        } else {
            openPanel.allowedFileTypes = ["ipa"]
        }
        openPanel.begin { (response) in
            guard let fileURL = openPanel.url, response == .OK else { return }
            self.installApplication(at: fileURL, to: device)
        }
    }
}

extension InstallationManager {
    enum InstallationStatus: String {
        case initializing = "initializing"
        case provisioning = "provisioning"
        case preparingIpa = "preparingIpa"
        case signing = "signing"
        case installing = "installing"
        case finished = "finished"
    }
}

extension InstallationManager: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        self.validate()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        self.validate()
    }

    private func validate() {
        guard let appleID = self.authenticationAppleIDTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = self.authenticationPasswordTextField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        if appleID.isEmpty || password.isEmpty {
            self.authenticationAlert?.buttons.first?.isEnabled = false
        } else {
            self.authenticationAlert?.buttons.first?.isEnabled = true
        }

        self.authenticationAlert?.layout()
    }
}
