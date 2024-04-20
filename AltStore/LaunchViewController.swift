//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas
import WidgetKit

import AltStoreCore

class LaunchViewController: RSTLaunchViewController
{
    private var didFinishLaunching = false
    
    private var destinationViewController: TabBarController!
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { (completionHandler) in
            DatabaseManager.shared.start(completionHandler: completionHandler)
        }

        return [isDatabaseStarted]
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return self.children.first
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.children.first
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Create destinationViewController now so view controllers can register for receiving Notifications.
        self.destinationViewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as? TabBarController
    }
}

extension LaunchViewController
{
    override func handleLaunchError(_ error: Error)
    {
        do
        {
            throw error
        }
        catch let error as NSError
        {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch AltStore", comment: "")
            
            let errorDescription: String
            
            if #available(iOS 14.5, *)
            {
                let errorMessages = [error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }
                errorDescription = errorMessages.joined(separator: "\n\n")
            }
            else
            {
                errorDescription = error.debugDescription
            }
            
            let alertController = UIAlertController(title: title, message: errorDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default, handler: { (action) in
                self.handleLaunchConditions()
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func finishLaunching()
    {
        super.finishLaunching()
        
        guard !self.didFinishLaunching else { return }
        
        AppManager.shared.update()
        AppManager.shared.updatePatronsIfNeeded()
        PatreonAPI.shared.refreshPatreonAccount()
        
        AppManager.shared.updateAllSources { result in
            guard case .failure(let error) = result else { return }
            Logger.main.error("Failed to update sources on launch. \(error.localizedDescription, privacy: .public)")
            
            let toastView = ToastView(error: error)
            toastView.addTarget(self.destinationViewController, action: #selector(TabBarController.presentSources), for: .touchUpInside)
            toastView.show(in: self.destinationViewController.selectedViewController ?? self.destinationViewController)
        }
        
        self.updateKnownSources()
        
        WidgetCenter.shared.reloadAllTimelines()
        
        // Add view controller as child (rather than presenting modally)
        // so tint adjustment + card presentations works correctly.
        self.destinationViewController.view.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        self.destinationViewController.view.alpha = 0.0
        self.addChild(self.destinationViewController)
        self.view.addSubview(self.destinationViewController.view, pinningEdgesWith: .zero)
        self.destinationViewController.didMove(toParent: self)
        
        UIView.animate(withDuration: 0.2) {
            self.destinationViewController.view.alpha = 1.0
        }
        
        self.didFinishLaunching = true
    }
}

private extension LaunchViewController
{
    func updateKnownSources()
    {
        AppManager.shared.updateKnownSources { result in
            switch result
            {
            case .failure(let error): print("[ALTLog] Failed to update known sources:", error)
            case .success((_, let blockedSources)):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                    let blockedSourceIDs = Set(blockedSources.lazy.map { $0.identifier })
                    let blockedSourceURLs = Set(blockedSources.lazy.compactMap { $0.sourceURL })
                    
                    let predicate = NSPredicate(format: "%K IN %@ OR %K IN %@",
                                                #keyPath(Source.identifier), blockedSourceIDs,
                                                #keyPath(Source.sourceURL), blockedSourceURLs)
                    
                    let sourceErrors = Source.all(satisfying: predicate, in: context).map { (source) in
                        let blockedSource = blockedSources.first { $0.identifier == source.identifier }
                        return SourceError.blocked(source, bundleIDs: blockedSource?.bundleIDs, existingSource: source)
                    }
                    
                    guard !sourceErrors.isEmpty else { return }
                                        
                    Task {
                        for error in sourceErrors
                        {
                            let title = String(format: NSLocalizedString("“%@” Blocked", comment: ""), error.$source.name)
                            let message = [error.localizedDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                            
                            await self.presentAlert(title: title, message: message)
                        }
                    }
                }
            }
        }
    }
}
