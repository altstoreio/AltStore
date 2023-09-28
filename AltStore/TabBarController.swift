//
//  TabBarController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AltStoreCore

extension TabBarController
{
    private enum Tab: Int, CaseIterable
    {
        case news
        case sources
        case browse
        case myApps
        case settings
    }
}

class TabBarController: UITabBarController
{
    private var initialSegue: (identifier: String, sender: Any?)?
    
    private var _viewDidAppear = false
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openPatreonSettings(_:)), name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.presentSources(_:)), name: AppDelegate.addSourceDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        _viewDidAppear = true
        
        if let (identifier, sender) = self.initialSegue
        {
            self.initialSegue = nil
            self.performSegue(withIdentifier: identifier, sender: sender)
        }
        else if let patchedApps = UserDefaults.standard.patchedApps, !patchedApps.isEmpty
        {
            // Check if we need to finish installing untethered jailbreak.
            let activeApps = InstalledApp.fetchActiveApps(in: DatabaseManager.shared.viewContext)
            guard let patchedApp = activeApps.first(where: { patchedApps.contains($0.bundleIdentifier) }) else { return }
            
            self.performSegue(withIdentifier: "finishJailbreak", sender: patchedApp)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard let identifier = segue.identifier else { return }
        
        switch identifier
        {
        case "finishJailbreak":
            guard let installedApp = sender as? InstalledApp else { return }
            
            let navigationController = segue.destination as! UINavigationController
            
            let patchViewController = navigationController.viewControllers.first as! PatchViewController
            patchViewController.installedApp = installedApp
            patchViewController.completionHandler = { [weak self] _ in
                self?.dismiss(animated: true, completion: nil)
            }
            
        default: break
        }
    }
    
    override func performSegue(withIdentifier identifier: String, sender: Any?)
    {
        guard _viewDidAppear else {
            self.initialSegue = (identifier, sender)
            return
        }
        
        super.performSegue(withIdentifier: identifier, sender: sender)
    }
}

extension TabBarController
{
    @objc func presentSources(_ sender: Any)
    {
        if let presentedViewController = self.presentedViewController
        {
            presentedViewController.dismiss(animated: true) {
                self.presentSources(sender)
            }
            
            return
        }
        
        guard let sourcesViewController = self.viewControllers?.lazy.compactMap({ $0 as? SourcesViewController }).first else { return }
        
        if let notification = (sender as? Notification), let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
        {
            sourcesViewController.deepLinkSourceURL = sourceURL
        }
        
        self.selectedViewController = sourcesViewController
    }
}

private extension TabBarController
{
    @objc func openPatreonSettings(_ notification: Notification)
    {
        self.selectedIndex = Tab.settings.rawValue
    }
    
    @objc func importApp(_ notification: Notification)
    {
        self.selectedIndex = Tab.myApps.rawValue
    }
    
    @objc func openErrorLog(_ notification: Notification)
    {
        self.selectedIndex = Tab.settings.rawValue
    }
}
