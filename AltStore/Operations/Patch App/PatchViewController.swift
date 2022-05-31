//
//  PatchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/20/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore
import AltSign
import Roxas

@available(iOS 14.0, *)
extension PatchViewController
{
    enum Step
    {
        case confirm
        case install
        case openApp
        case patchApp
        case reboot
        case refresh
        case finish
    }
}

@available(iOS 14.0, *)
class PatchViewController: UIViewController
{
    var patchApp: AnyApp?
    var installedApp: InstalledApp?
    
    var completionHandler: ((Result<Void, Error>) -> Void)?
    
    private let context = AuthenticatedOperationContext()
    
    private var currentStep: Step = .confirm {
        didSet {
            DispatchQueue.main.async {
                self.update()
            }
        }
    }
    
    private var buttonHandler: (() -> Void)?
    private var resignedApp: ALTApplication?
    
    private lazy var temporaryDirectory: URL = FileManager.default.uniqueTemporaryURL()
    
    private var didEnterBackgroundObservation: NSObjectProtocol?
    private weak var cancellableProgress: Progress?
    
    @IBOutlet private var placeholderView: RSTPlaceholderView!
    @IBOutlet private var taskDescriptionLabel: UILabel!
    @IBOutlet private var pillButton: PillButton!
    @IBOutlet private var cancelBarButtonItem: UIBarButtonItem!
    @IBOutlet private var cancelButton: UIButton!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.isModalInPresentation = true
        
        self.placeholderView.stackView.spacing = 20
        self.placeholderView.textLabel.textColor = .white
        
        self.placeholderView.detailTextLabel.textAlignment = .left
        self.placeholderView.detailTextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        
        self.buttonHandler = { [weak self] in
            self?.startProcess()
        }
        
        do
        {
            try FileManager.default.createDirectory(at: self.temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        catch
        {
            print("Failed to create temporary directory:", error)
        }
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if self.installedApp != nil
        {
            self.refreshApp()
        }
    }
}

@available(iOS 14.0, *)
private extension PatchViewController
{
    func update()
    {
        self.cancelButton.alpha = 0.0
        
        switch self.currentStep
        {
        case .confirm:
            guard let app = self.patchApp else { break }
            
            if UIDevice.current.isUntetheredJailbreakRequired
            {
                self.placeholderView.textLabel.text = NSLocalizedString("Jailbreak Requires Untethering", comment: "")
                self.placeholderView.detailTextLabel.text = String(format: NSLocalizedString("This jailbreak is untethered, which means %@ will never expire — even after 7 days or rebooting the device.\n\nInstalling an untethered jailbreak requires a few extra steps, but AltStore will walk you through the process.\n\nWould you like to continue? ", comment: ""), app.name)
            }
            else
            {
                self.placeholderView.textLabel.text = NSLocalizedString("Jailbreak Supports Untethering", comment: "")
                self.placeholderView.detailTextLabel.text = String(format: NSLocalizedString("This jailbreak has an untethered version, which means %@ will never expire — even after 7 days or rebooting the device.\n\nInstalling an untethered jailbreak requires a few extra steps, but AltStore will walk you through the process.\n\nWould you like to continue? ", comment: ""), app.name)
            }
            
            self.pillButton.setTitle(NSLocalizedString("Install Untethered Jailbreak", comment: ""), for: .normal)
            
            self.cancelButton.alpha = 1.0
            
        case .install:
            guard let app = self.patchApp else { break }
            
            self.placeholderView.textLabel.text = String(format: NSLocalizedString("Installing %@ placeholder…", comment: ""), app.name)
            self.placeholderView.detailTextLabel.text = NSLocalizedString("A placeholder app needs to be installed in order to prepare your device for untethering.\n\nThis may take a few moments.", comment: "")
            
        case .openApp:
            self.placeholderView.textLabel.text = NSLocalizedString("Continue in App", comment: "")
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Please open the placeholder app and follow the instructions to continue jailbreaking your device.", comment: "")
            
            self.pillButton.setTitle(NSLocalizedString("Open Placeholder", comment: ""), for: .normal)
            
        case .patchApp:
            guard let app = self.patchApp else { break }
            
            self.placeholderView.textLabel.text = String(format: NSLocalizedString("Patching %@ placeholder…", comment: ""), app.name)
            self.placeholderView.detailTextLabel.text = NSLocalizedString("This will take a few moments. Please do not turn off the screen or leave the app until patching is complete.", comment: "")
            
            self.pillButton.setTitle(NSLocalizedString("Patch Placeholder", comment: ""), for: .normal)
          
        case .reboot:
            self.placeholderView.textLabel.text = NSLocalizedString("Continue in App", comment: "")
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Please open the placeholder app and follow the instructions to continue jailbreaking your device.", comment: "")
            
            self.pillButton.setTitle(NSLocalizedString("Open Placeholder", comment: ""), for: .normal)
            
        case .refresh:
            guard let installedApp = self.installedApp else { break }
            
            self.placeholderView.textLabel.text = String(format: NSLocalizedString("Finish installing %@?", comment: ""), installedApp.name)
            self.placeholderView.detailTextLabel.text = String(format: NSLocalizedString("In order to finish jailbreaking this device, you need to install %@ then follow the instructions in the app.", comment: ""), installedApp.name)
            
            self.pillButton.setTitle(String(format: NSLocalizedString("Install %@", comment: ""), installedApp.name), for: .normal)
            
        case .finish:
            guard let installedApp = self.installedApp else { break }
            
            self.placeholderView.textLabel.text = String(format: NSLocalizedString("Finish in %@", comment: ""), installedApp.name)
            self.placeholderView.detailTextLabel.text = String(format: NSLocalizedString("Follow the instructions in %@ to finish jailbreaking this device.", comment: ""), installedApp.name)
            
            self.pillButton.setTitle(String(format: NSLocalizedString("Open %@", comment: ""), installedApp.name), for: .normal)
        }
    }
    
    func present(_ error: Error, title: String)
    {
        DispatchQueue.main.async {
            let nsError = error as NSError
            
            let alertController = UIAlertController(title: nsError.localizedFailure ?? title, message: error.localizedDescription, preferredStyle: .alert)
            alertController.addAction(.ok)
            self.present(alertController, animated: true, completion: nil)
            
            self.setProgress(nil, description: nil)
        }
    }
    
    func setProgress(_ progress: Progress?, description: String?)
    {
        DispatchQueue.main.async {
            self.pillButton.progress = progress
            self.taskDescriptionLabel.text = description ?? " " // Use non-empty string to prevent label resizing itself.
        }
    }
    
    func finish(with result: Result<Void, Error>)
    {
        do
        {
            try FileManager.default.removeItem(at: self.temporaryDirectory)
        }
        catch
        {
            print("Failed to remove temporary directory:", error)
        }
        
        if let observation = self.didEnterBackgroundObservation
        {
            NotificationCenter.default.removeObserver(observation)
        }
        
        self.completionHandler?(result)
        self.completionHandler = nil
    }
}

@available(iOS 14.0, *)
private extension PatchViewController
{
    @IBAction func performButtonAction()
    {
        self.buttonHandler?()
    }
    
    @IBAction func cancel()
    {
        self.finish(with: .success(()))
        
        self.cancellableProgress?.cancel()
    }
    
    @IBAction func installRegularJailbreak()
    {
        guard let app = self.patchApp else { return }
        
        let title: String
        let message: String
        
        if UIDevice.current.isUntetheredJailbreakRequired
        {
            title = NSLocalizedString("Untethering Required", comment: "")
            message = String(format: NSLocalizedString("%@ can not jailbreak this device unless you untether it first. Are you sure you want to install without untethering?", comment: ""), app.name)
        }
        else
        {
            title = NSLocalizedString("Untethering Recommended", comment: "")
            message = String(format: NSLocalizedString("Untethering this jailbreak will prevent %@ from expiring, even after 7 days or rebooting the device. Are you sure you want to install without untethering?", comment: ""), app.name)
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Install Without Untethering", comment: ""), style: .default) { _ in
            self.finish(with: .failure(OperationError.cancelled))
        })
        alertController.addAction(.cancel)
        self.present(alertController, animated: true, completion: nil)
    }
}

@available(iOS 14.0, *)
private extension PatchViewController
{
    func startProcess()
    {
        guard let patchApp = self.patchApp else { return }
        
        self.currentStep = .install
        
        if let progress = AppManager.shared.installationProgress(for: patchApp)
        {
            // Cancel pending jailbreak app installation so we can start a new one.
            progress.cancel()
        }
        
        let appURL = InstalledApp.fileURL(for: patchApp)
        let cachedAppURL = self.temporaryDirectory.appendingPathComponent("Cached.app")
        
        do
        {
            // Make copy of original app, so we can replace the cached patch app with it later.
            try FileManager.default.copyItem(at: appURL, to: cachedAppURL, shouldReplace: true)
        }
        catch
        {
            self.present(error, title: NSLocalizedString("Could not back up jailbreak app.", comment: ""))
            return
        }
        
        var unzippingError: Error?
        let refreshGroup = AppManager.shared.install(patchApp, presentingViewController: self, context: self.context) { result in
            do
            {
                _ = try result.get()
                
                if let unzippingError = unzippingError
                {
                    throw unzippingError
                }
                
                // Replace cached patch app with original app so we can resume installing it post-reboot.
                try FileManager.default.copyItem(at: cachedAppURL, to: appURL, shouldReplace: true)
                
                self.openApp()
            }
            catch
            {
                self.present(error, title: String(format: NSLocalizedString("Could not install %@ placeholder.", comment: ""), patchApp.name))
            }
        }
        refreshGroup.beginInstallationHandler = { (installedApp) in
            do
            {
                // Replace patch app name with correct name.
                installedApp.name = patchApp.name
                
                let ipaURL = installedApp.refreshedIPAURL
                let resignedAppURL = try FileManager.default.unzipAppBundle(at: ipaURL, toDirectory: self.temporaryDirectory)
                
                self.resignedApp = ALTApplication(fileURL: resignedAppURL)
            }
            catch
            {
                print("Error unzipping app bundle:", error)
                unzippingError = error
            }
        }
        self.setProgress(refreshGroup.progress, description: nil)
        
        self.cancellableProgress = refreshGroup.progress
    }
    
    func openApp()
    {
        guard let patchApp = self.patchApp else { return }
        
        self.setProgress(nil, description: nil)
        self.currentStep = .openApp
        
        // This observation is willEnterForeground because patching starts immediately upon return.
        self.didEnterBackgroundObservation = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { (notification) in
            self.didEnterBackgroundObservation.map { NotificationCenter.default.removeObserver($0) }
            self.patchApplication()
        }
        
        self.buttonHandler = { [weak self] in
            guard let self = self else { return }
            
            #if !targetEnvironment(simulator)
            
            let openURL = InstalledApp.openAppURL(for: patchApp)
            UIApplication.shared.open(openURL) { success in
                guard !success else { return }
                self.present(OperationError.openAppFailed(name: patchApp.name), title: String(format: NSLocalizedString("Could not open %@ placeholder.", comment: ""), patchApp.name))
            }
            
            #endif
        }
    }
    
    func patchApplication()
    {
        guard let resignedApp = self.resignedApp else { return }
        
        self.currentStep = .patchApp
        
        self.buttonHandler = { [weak self] in
            self?.patchApplication()
        }
        
        let patchAppOperation = AppManager.shared.patch(resignedApp: resignedApp, presentingViewController: self, context: self.context) { result in
            switch result
            {
            case .failure(let error): self.present(error, title: String(format: NSLocalizedString("Could not patch %@ placeholder.", comment: ""), resignedApp.name))
            case .success: self.rebootDevice()
            }
        }
        patchAppOperation.progressHandler = { (progress, description) in
            self.setProgress(progress, description: description)
        }
        self.cancellableProgress = patchAppOperation.progress
    }
    
    func rebootDevice()
    {
        guard let patchApp = self.patchApp else { return }
        
        self.setProgress(nil, description: nil)
        self.currentStep = .reboot
        
        self.didEnterBackgroundObservation = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { (notification) in
            self.didEnterBackgroundObservation.map { NotificationCenter.default.removeObserver($0) }
            
            var patchedApps = UserDefaults.standard.patchedApps ?? []
            if !patchedApps.contains(patchApp.bundleIdentifier)
            {
                patchedApps.append(patchApp.bundleIdentifier)
                UserDefaults.standard.patchedApps = patchedApps
            }
            
            self.finish(with: .success(()))
        }

        self.buttonHandler = { [weak self] in
            guard let self = self else { return }
            
            #if !targetEnvironment(simulator)
            
            let openURL = InstalledApp.openAppURL(for: patchApp)
            UIApplication.shared.open(openURL) { success in
                guard !success else { return }
                self.present(OperationError.openAppFailed(name: patchApp.name), title: String(format: NSLocalizedString("Could not open %@ placeholder.", comment: ""), patchApp.name))
            }
            
            #endif
        }
    }
    
    func refreshApp()
    {
        guard let installedApp = self.installedApp else { return }
        
        self.currentStep = .refresh
        
        self.buttonHandler = { [weak self] in
            guard let self = self else { return }
            DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                let tempApp = context.object(with: installedApp.objectID) as! InstalledApp
                tempApp.needsResign = true
                
                let errorTitle = String(format: NSLocalizedString("Could not install %@.", comment: ""), tempApp.name)
                
                do
                {
                    try context.save()
                    
                    installedApp.managedObjectContext?.perform {
                        // Refreshing ensures we don't attempt to patch the app again,
                        // since that is only checked when installing a new app.
                        let refreshGroup = AppManager.shared.refresh([installedApp], presentingViewController: self, group: nil)
                        refreshGroup.completionHandler = { [weak refreshGroup, weak self] (results) in
                            guard let self = self else { return }
                            
                            do
                            {
                                guard let (bundleIdentifier, result) = results.first else { throw refreshGroup?.context.error ?? OperationError.unknown }
                                _ = try result.get()
                                
                                if var patchedApps = UserDefaults.standard.patchedApps, let index = patchedApps.firstIndex(of: bundleIdentifier)
                                {
                                    patchedApps.remove(at: index)
                                    UserDefaults.standard.patchedApps = patchedApps
                                }
                                
                                self.finish()
                            }
                            catch
                            {
                                self.present(error, title: errorTitle)
                            }
                        }
                        self.setProgress(refreshGroup.progress, description: String(format: NSLocalizedString("Installing %@...", comment: ""), installedApp.name))
                    }
                }
                catch
                {
                    self.present(error, title: errorTitle)
                }
            }
        }
    }
    
    func finish()
    {
        guard let installedApp = self.installedApp else { return }
        
        self.setProgress(nil, description: nil)
        self.currentStep = .finish
        
        self.didEnterBackgroundObservation = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { (notification) in
            self.didEnterBackgroundObservation.map { NotificationCenter.default.removeObserver($0) }
            self.finish(with: .success(()))
        }
        
        installedApp.managedObjectContext?.perform {
            let appName = installedApp.name
            let openURL = installedApp.openAppURL
            
            self.buttonHandler = { [weak self] in
                guard let self = self else { return }
                
                #if !targetEnvironment(simulator)
                
                UIApplication.shared.open(openURL) { success in
                    guard !success else { return }
                    self.present(OperationError.openAppFailed(name: appName), title: String(format: NSLocalizedString("Could not open %@.", comment: ""), appName))
                }
                
                #endif
            }
        }
    }
}
