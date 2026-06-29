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

        /// Stable identifier used to look up the matching `UITab` when the
        /// iPad sidebar is active (the legacy `selectedIndex` no longer maps
        /// 1:1 to the tabs once they're grouped into sections).
        var identifier: String
        {
            switch self
            {
            case .news: return "news"
            case .sources: return "sources"
            case .browse: return "browse"
            case .myApps: return "myApps"
            case .settings: return "settings"
            }
        }

        /// Localized title shown in the iPad sidebar.
        var sidebarTitle: String
        {
            switch self
            {
            case .news: return NSLocalizedString("News", comment: "")
            case .sources: return NSLocalizedString("Sources", comment: "")
            case .browse: return NSLocalizedString("Browse", comment: "")
            case .myApps: return NSLocalizedString("My Apps", comment: "")
            case .settings: return NSLocalizedString("Settings", comment: "")
            }
        }

        /// SF Symbol used for the sidebar/tab. Kept separate from the iPhone
        /// tab bar artwork so the phone UI stays exactly as it is today.
        var sidebarSymbolName: String
        {
            switch self
            {
            case .news: return "newspaper"
            case .sources: return "books.vertical"
            case .browse: return "bag"
            case .myApps: return "square.stack.3d.up"
            case .settings: return "gearshape"
            }
        }
    }
}

class TabBarController: UITabBarController
{
    private var initialSegue: (identifier: String, sender: Any?)?
    
    private var _viewDidAppear = false

    private var sourcesViewController: SourcesViewController!
    private var featuredViewController: FeaturedViewController!

    /// `true` once the iPad sidebar (iOS 18 `.tabSidebar`) has been configured,
    /// at which point navigation goes through `selectedTab` instead of `selectedIndex`.
    private var didConfigureSidebar = false
    
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

        // On iPad, present the tabs as a sidebar (iOS 18+). iPhone keeps the tab bar.
        if #available(iOS 18, *)
        {
            self.configureSidebar()
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

        self.select(.sources)
    }
}

private extension TabBarController
{
    @objc func openPatreonSettings(_ notification: Notification)
    {
        self.select(.settings)
    }

    @objc func importApp(_ notification: Notification)
    {
        self.select(.myApps)
    }

    @objc func openErrorLog(_ notification: Notification)
    {
        self.select(.settings)
    }

    @objc func openBrowseTab(_ notification: Notification)
    {
        self.select(.browse)
        
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
        self.select(.browse)

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

private extension TabBarController
{
    /// Selects a tab whether we're showing the iPhone tab bar (index-based) or the
    /// iPad sidebar (identity-based via `UITab`, which is robust to any future
    /// reordering or grouping of the sidebar tabs).
    private func select(_ tab: Tab)
    {
        if #available(iOS 18, *), self.didConfigureSidebar, let sidebarTab = self.sidebarTab(for: tab)
        {
            self.selectedTab = sidebarTab
        }
        else
        {
            self.selectedIndex = tab.rawValue
        }
    }
}

@available(iOS 18, *)
private extension TabBarController
{
    /// Presents the tabs as an iPad sidebar (App Store / Music style) while keeping
    /// the bottom tab bar in compact widths. iPhone never reaches here.
    func configureSidebar()
    {
        // Use the device idiom rather than `traitCollection`: in `viewDidLoad` the
        // view isn't in the window yet, so its trait collection can still report an
        // `.unspecified` idiom.
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        // Capture the storyboard-instantiated navigation controllers *before* we
        // replace `viewControllers` via `tabs`, so each `UITab` reuses the exact
        // same instance. This preserves every deep link and the CoreData fetched
        // results controllers already wired up inside them. We filter to navigation
        // controllers because `viewControllers` may also contain the invisible
        // `AppTrackerView` hosting controller added for marketplace install tracking.
        let navigationControllers = (self.viewControllers ?? []).compactMap { $0 as? UINavigationController }
        guard navigationControllers.count == Tab.allCases.count else { return }

        func makeTab(_ tab: Tab) -> UITab
        {
            let viewController = navigationControllers[tab.rawValue]
            return UITab(title: tab.sidebarTitle, image: UIImage(systemName: tab.sidebarSymbolName), identifier: tab.identifier) { _ in
                viewController
            }
        }

        // Keep the same order + initial selection as the iPhone tab bar so launch
        // behavior is identical (the first tab is shown while sources refresh).
        let newsTab = makeTab(.news)
        self.tabs = [newsTab, makeTab(.sources), makeTab(.browse), makeTab(.myApps), makeTab(.settings)]
        self.mode = .tabSidebar
        self.selectedTab = newsTab

        // Show the sidebar and tile it beside the content (rather than overlapping
        // it), so the detail column reports its own visible width. With overlap the
        // content spans the full window *under* the sidebar, which pushes a grid's
        // first column behind it. In portrait iOS collapses the tiled sidebar to a
        // top strip (tap the toggle to reveal it); in landscape it stays alongside.
        self.sidebar.isHidden = false
        self.sidebar.preferredLayout = .tile

        self.didConfigureSidebar = true
    }

    /// Finds the sidebar `UITab` that backs a given `Tab`.
    private func sidebarTab(for tab: Tab) -> UITab?
    {
        return self.tabs.first { $0.identifier == tab.identifier }
    }
}
