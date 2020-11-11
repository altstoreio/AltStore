//
//  TabBarController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension TabBarController
{
    private enum Tab: Int, CaseIterable
    {
        case news
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
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "presentSources",
              let notification = sender as? Notification,
              let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
        else { return }
        
        let navigationController = segue.destination as! UINavigationController
        let sourcesViewController = navigationController.viewControllers.first as! SourcesViewController
        sourcesViewController.deepLinkSourceURL = sourceURL
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
            if let navigationController = presentedViewController as? UINavigationController,
               let sourcesViewController = navigationController.viewControllers.first as? SourcesViewController
            {
                if let notification = (sender as? Notification),
                   let sourceURL = notification.userInfo?[AppDelegate.addSourceDeepLinkURLKey] as? URL
                {
                    sourcesViewController.deepLinkSourceURL = sourceURL
                }
                else
                {
                    // Don't dismiss SourcesViewController if it's already presented.
                }
            }
            else
            {
                presentedViewController.dismiss(animated: true) {
                    self.presentSources(sender)
                }
            }
            
            return
        }
        
        self.performSegue(withIdentifier: "presentSources", sender: sender)
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
}
