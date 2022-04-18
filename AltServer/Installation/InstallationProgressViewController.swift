//
//  InstallationProgressViewController.swift
//  AltServer
//
//  Created by royal on 09/01/2022.
//

import Cocoa
import AltSign

final class InstallationProgressViewController: NSViewController {
    private var fileURL: URL?
    private var deviceName: String?
    private var onFinish: (() -> Void)?

    @IBOutlet weak var startLabel: InstallationProgressViewStatusLabel!
    @IBOutlet weak var provisionLabel: InstallationProgressViewStatusLabel!
    @IBOutlet weak var ipaLabel: InstallationProgressViewStatusLabel!
    @IBOutlet weak var signLabel: InstallationProgressViewStatusLabel!
    @IBOutlet weak var installLabel: InstallationProgressViewStatusLabel!

    override func viewDidDisappear() {
        super.viewDidDisappear()
        NotificationCenter.default.removeObserver(self, name: .installationStatusNotification, object: nil)
    }

    public func setup(fileURL: URL, device: ALTDevice, onFinish: @escaping () -> Void) {
        self.fileURL = fileURL
        self.deviceName = device.name
        self.onFinish = onFinish

        NotificationCenter.default.addObserver(self, selector: #selector(handleInstallationStatusUpdate), name: .installationStatusNotification, object: nil)
    }

    @objc private func handleInstallationStatusUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any],
              let status = userInfo["status"] as? String else {
            return
        }

        print("☔️", status, userInfo)

        DispatchQueue.main.async { [self] in
            switch InstallationManager.InstallationStatus(rawValue: status) {
                case .initializing:
                    startLabel.update(status: .current)
                    provisionLabel.update(status: .pending)
                    ipaLabel.update(status: .pending)
                    signLabel.update(status: .pending)
                    installLabel.update(status: .pending)
                case .provisioning:
                    startLabel.update(status: .done)
                    provisionLabel.update(status: .current)
                    ipaLabel.update(status: .pending)
                    signLabel.update(status: .pending)
                    installLabel.update(status: .pending)
                case .preparingIpa:
                    startLabel.update(status: .done)
                    provisionLabel.update(status: .done)
                    ipaLabel.update(status: .current)
                    if let progress = userInfo["progress"] as? Double {
                        ipaLabel.progress = progress
                    }
                    signLabel.update(status: .pending)
                    installLabel.update(status: .pending)
                case .signing:
                    startLabel.update(status: .done)
                    provisionLabel.update(status: .done)
                    ipaLabel.update(status: .done)
                    signLabel.update(status: .current)
                    installLabel.update(status: .pending)
                case .installing:
                    startLabel.update(status: .done)
                    provisionLabel.update(status: .done)
                    ipaLabel.update(status: .done)
                    signLabel.update(status: .done)
                    installLabel.update(status: .current)
                    if let progress = userInfo["progress"] as? Double {
                        installLabel.progress = progress
                    }
                case .finished:
                    startLabel.update(status: .done)
                    provisionLabel.update(status: .done)
                    ipaLabel.update(status: .done)
                    signLabel.update(status: .done)
                    
                    let success = userInfo["success"] as? Bool
                    if success != nil && (success ?? false) {
                        installLabel.update(status: .done)
                    } else if let error = userInfo["error"] as? Error {
                        installLabel.update(status: .failed)
                        installLabel.string = error.localizedDescription
                    } else {
                        installLabel.update(status: .failed)
                        installLabel.string = "Some error occured!"
                    }
                    onFinish?()
                default:
                    break
            }
        }
    }
}
