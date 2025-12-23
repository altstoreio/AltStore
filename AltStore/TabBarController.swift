//
//  TabBarController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

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
    
    private var sourcesViewController: SourcesViewController!
    private var featuredViewController: FeaturedViewController!
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openPatreonSettings(_:)), name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.presentSources(_:)), name: AppDelegate.addSourceDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.openBrowseTab(_:)), name: AppDelegate.searchDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabBarController.viewApp(_:)), name: AppDelegate.viewAppDeepLinkNotification, object: nil)
    }
    
    override func viewDidLoad() 
    {
        super.viewDidLoad()
        
        let browseNavigationController = self.viewControllers![Tab.browse.rawValue] as! UINavigationController
        browseNavigationController.tabBarItem.image = UIImage(systemName: "bag")
        self.featuredViewController = browseNavigationController.viewControllers.first as? FeaturedViewController
        
        let sourcesNavigationController = self.viewControllers![Tab.sources.rawValue] as! UINavigationController
        self.sourcesViewController = sourcesNavigationController.viewControllers.first as? SourcesViewController
        
        if #available(iOS 18, *)
        {
            let hostingController = UIHostingController(rootView: AppTrackerView(tracker: AppMarketplace.shared.tracker))
            hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostingController.view.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
            hostingController.view.alpha = 0.0
            self.addChild(hostingController)
            self.view.insertSubview(hostingController.view, at: 0)
            hostingController.didMove(toParent: self)
        }
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
                
        if let notification = (sender as? Notification), let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
        {
            self.loadViewIfNeeded() // Initialize sourcesViewController
            self.sourcesViewController?.deepLinkSourceURL = sourceURL
        }
        
        self.selectedIndex = Tab.sources.rawValue
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
    
    @objc func openBrowseTab(_ notification: Notification)
    {
        self.selectedIndex = Tab.browse.rawValue
        
        if let query = notification.userInfo?[AppDelegate.searchDeepLinkQueryKey] as? String
        {
            self.featuredViewController.loadViewIfNeeded()
            self.featuredViewController.searchController.searchBar.text = query
            
            self.featuredViewController.navigationController?.popToRootViewController(animated: false)
            
            // Slight delay to ensure the search controller is actually presented (YOLO).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.featuredViewController.searchController.isActive = true
                self.featuredViewController.searchController.updateSearchResults(for: self.featuredViewController.searchController)
            }
        }
    }
    
    @objc func viewApp(_ notification: Notification)
    {
        self.selectedIndex = Tab.browse.rawValue
        
        if let presentedViewController = self.presentedViewController
        {
            presentedViewController.dismiss(animated: true) {
                self.viewApp(notification)
            }
            
            return
        }
        
        guard let storeApp = notification.userInfo?[AppDelegate.viewAppDeepLinkStoreAppKey] as? StoreApp else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.featuredViewController.navigationController?.pushViewController(appViewController, animated: true)
    }
}
