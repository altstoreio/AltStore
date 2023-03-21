//
//  HeaderContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

private var navigationBarPropertyAnimatorKey = 0

// A UIViewController that manipulates its navigation controller's navigation bar.
protocol NavigationBarAnimator: UIViewController {}

protocol ScrollableContentViewController: UIViewController
{
    var scrollView: UIScrollView { get }
}

//extension UINavigationBar
//{
//    var propertyAnimator: UIViewPropertyAnimator? {
//        get { objc_getAssociatedObject(self, &navigationBarPropertyAnimatorKey) as? UIViewPropertyAnimator }
//        set { objc_setAssociatedObject(self, &navigationBarPropertyAnimatorKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)}
//    }
//}

class TestTableViewController: UITableViewController, ScrollableContentViewController
{
    lazy var dataSource = self.makeDataSource()
    
    var scrollView: UIScrollView { self.tableView }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        self.tableView.rowHeight = 100
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: RSTCellContentGenericCellIdentifier)
    }
    
    func makeDataSource() -> RSTArrayTableViewDataSource<NSString>
    {
        let dataSource = RSTArrayTableViewDataSource(items: ["Riley", "Shane", "Caroline"/*, "Ryan", "Josh"*/] as [NSString])
        dataSource.cellConfigurationHandler = { (cell, name, indexPath) in
            cell.textLabel?.text = name as String
        }
        
        return dataSource
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp.bundleIdentifier), "com.rileytestut.Delta")
        let storeApp = StoreApp.first(satisfying: predicate, in: DatabaseManager.shared.viewContext)!
        
        let appsViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appsViewController, animated: true)
    }
}

class TestViewController: HeaderContentViewController<UIView, TestTableViewController>
{
    override init()
    {
        super.init()
        
        self.title = NSLocalizedString("Test", comment: "")
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tintColor = .systemOrange
    }
    
    override func makeContentViewController() -> TestTableViewController
    {
        TestTableViewController(style: .plain)
    }
    
    override func makeHeaderView() -> UIVisualEffectView
    {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.frame.size = CGSize(width: 200, height: 100)
        return view
    }
}

class HeaderContentViewController<Header: UIView, Content: UIViewController & ScrollableContentViewController> : UIViewController, NavigationBarAnimator, UIAdaptivePresentationControllerDelegate, UIScrollViewDelegate
{
    var tintColor: UIColor! {
        get { self.view.tintColor }
        set {
            self.view.tintColor = newValue
            self.update()
        }
    }
    
    private(set) var headerView: Header!
    private(set) var contentViewController: Content!
    
    private var scrollView: UIScrollView!
    private var headerScrollView: UIScrollView!
    private var contentViewControllerShadowView: UIView!
    
    private var backButton: UIButton!
//    private(set) var backButtonContainerView: UIVisualEffectView!
    
    private(set) var backgroundImageView: UIImageView!
    private var backgroundBlurView: UIVisualEffectView!
    
    private(set) var navigationBarNameLabel: UILabel!
    private(set) var navigationBarIconView: UIImageView!
    private(set) var navigationBarButton: PillButton!
    private(set) var navigationBarTitleView: UIStackView!
    
    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?
    private var contentSizeObservation: NSKeyValueObservation?
    
//    private var ignoreBackGestureRecognizer: UIPanGestureRecognizer!
//    private var ignoreHeaderPanGestureRecognizer: UIPanGestureRecognizer!
    
    private var _shouldResetLayout = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    
//    private var _viewDidAppear = false
//    private var _previousNavigationBarHidden: Bool?
    
    private var _preferredStatusBarStyle: UIStatusBarStyle = .default
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return _preferredStatusBarStyle
    }
    
    private var shouldHideNavigationBar = true
    
    init()
    {
        super.init(nibName: nil, bundle: nil)
    }
    
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func makeContentViewController() -> Content
    {
        fatalError()
    }
    
    func makeHeaderView() -> Header
    {
        fatalError()
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = .white
        self.view.clipsToBounds = true
        
        self.navigationItem.largeTitleDisplayMode = .never
        self.navigationController?.presentationController?.delegate = self
        
        // Background
        self.backgroundImageView = UIImageView(frame: .zero)
        self.view.addSubview(self.backgroundImageView)
        
        let blurEffect = UIBlurEffect(style: .regular)
        self.backgroundBlurView = UIVisualEffectView(effect: blurEffect)
        self.view.addSubview(self.backgroundBlurView, pinningEdgesWith: .zero)
                
        
        // Header View
        self.headerScrollView = UIScrollView(frame: .zero)
        self.headerScrollView.delegate = self
        self.headerScrollView.isPagingEnabled = true
        self.headerScrollView.clipsToBounds = false
        self.headerScrollView.indicatorStyle = .white
        self.headerScrollView.showsVerticalScrollIndicator = false
        self.view.addSubview(self.headerScrollView)
        
        self.headerView = self.makeHeaderView()
        self.headerView.translatesAutoresizingMaskIntoConstraints = true
        self.headerScrollView.addSubview(self.headerView)
        
        if #available(iOS 15, *)
        {
            var backgroundConfiguration = UIBackgroundConfiguration.clear()
            backgroundConfiguration.visualEffect = UIBlurEffect(style: .systemThinMaterial)
            
            let imageConfiguration = UIImage.SymbolConfiguration(weight: .semibold)
            let image = UIImage(systemName: "chevron.backward", withConfiguration: imageConfiguration)
            
            var configuration = UIButton.Configuration.plain()
            configuration.cornerStyle = .capsule
            configuration.background = backgroundConfiguration
            configuration.image = image
            
            self.backButton = UIButton(configuration: configuration)
        }
        else
        {
            self.backButton = UIButton(type: .system)
            self.backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
            self.backButton.backgroundColor = .white.withAlphaComponent(0.7)
            self.backButton.sizeToFit()
            self.backButton.clipsToBounds = true
            self.backButton.layer.cornerRadius = self.backButton.bounds.midY
        }
        
        self.backButton.addTarget(self.navigationController, action: #selector(UINavigationController.popViewController(animated:)), for: .primaryActionTriggered)
        self.view.addSubview(self.backButton)
        
        // Content View Controller
        self.contentViewController = self.makeContentViewController()
        self.contentViewController.view.frame = self.view.bounds
        self.contentViewController.view.layer.cornerRadius = 38
        self.contentViewController.view.layer.masksToBounds = true
        
        self.addChild(self.contentViewController)
        self.view.addSubview(self.contentViewController.view)
        self.contentViewController.didMove(toParent: self)
        
        self.contentViewControllerShadowView = UIView()
        self.contentViewControllerShadowView.backgroundColor = .white
        self.contentViewControllerShadowView.layer.cornerRadius = 38
        self.contentViewControllerShadowView.layer.shadowColor = UIColor.black.cgColor
        self.contentViewControllerShadowView.layer.shadowOffset = CGSize(width: 0, height: -1)
        self.contentViewControllerShadowView.layer.shadowRadius = 10
        self.contentViewControllerShadowView.layer.shadowOpacity = 0.3
        self.view.insertSubview(self.contentViewControllerShadowView, belowSubview: self.contentViewController.view)
                
        // Add to front so the scroll indicators are visible, but disable user interaction.
        self.scrollView = UIScrollView(frame: CGRect(origin: .zero, size: self.view.bounds.size))
        self.scrollView.delegate = self
        self.scrollView.isUserInteractionEnabled = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.view.addSubview(self.scrollView, pinningEdgesWith: .zero)
        self.view.addGestureRecognizer(self.scrollView.panGestureRecognizer)
        
        self.contentViewController.scrollView.panGestureRecognizer.require(toFail: self.scrollView.panGestureRecognizer)
        self.contentViewController.scrollView.showsVerticalScrollIndicator = false
        self.contentViewController.scrollView.contentInsetAdjustmentBehavior = .never
        
        
        // Navigation Bar Title View
        self.navigationBarNameLabel = UILabel(frame: .zero)
        self.navigationBarNameLabel.font = UIFont.boldSystemFont(ofSize: 17) // We want semibold, which this (apparently) returns.
        self.navigationBarNameLabel.text = self.title
        self.navigationBarNameLabel.sizeToFit()
        
        self.navigationBarIconView = UIImageView(frame: .zero)
        self.navigationBarIconView.translatesAutoresizingMaskIntoConstraints = false
        self.navigationBarIconView.clipsToBounds = true
        
        self.navigationBarTitleView = UIStackView(arrangedSubviews: [self.navigationBarIconView, self.navigationBarNameLabel])
        self.navigationBarTitleView.axis = .horizontal
        self.navigationBarTitleView.spacing = 8
        
        NSLayoutConstraint.activate([
            self.navigationBarIconView.widthAnchor.constraint(equalToConstant: 35),
            self.navigationBarIconView.heightAnchor.constraint(equalTo: self.navigationBarIconView.widthAnchor)
        ])
        
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
        
        let size = self.navigationBarTitleView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.navigationBarTitleView.bounds.size = size
        self.navigationItem.titleView = self.navigationBarTitleView
        
        self._backgroundBlurEffect = self.backgroundBlurView.effect as? UIBlurEffect
        self._backgroundBlurTintColor = self.backgroundBlurView.contentView.backgroundColor
        
        self.contentSizeObservation = self.contentViewController.scrollView.observe(\.contentSize, options: [.new, .old]) { [weak self] (scrollView, change) in
            guard let size = change.newValue, let previousSize = change.oldValue, size != previousSize else { return }
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
        
        self.update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        if #available(iOS 15, *)
        {
            // Fix navigation bar + tab bar appearance on iOS 15.
            self.setContentScrollView(self.scrollView)
            self.navigationItem.scrollEdgeAppearance = self.navigationController?.navigationBar.standardAppearance
        }
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        self.prepareBlur()
        
        // Update blur immediately.
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        
        self.transitionCoordinator?.animate(alongsideTransition: { (context) in
            if self.shouldHideNavigationBar
            {
                self.hideNavigationBar()
            }
            else
            {
                self.showNavigationBar()
            }
        }, completion: nil)
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        self._shouldResetLayout = true
//        self._viewDidAppear = true
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool)
    {
        super.viewWillDisappear(animated)

        // Guard against "dismissing" when presenting via 3D Touch pop.
        // Also store reference since self.navigationController will be nil after disappearing.
        guard let navigationController = self.navigationController else { return }
        
        self.navigationBarAnimator?.stopAnimation(true)
        
        if let topViewController = navigationController.topViewController
        {
            if let navigationBarAnimator = topViewController as? NavigationBarAnimator
            {
                // Showing NavigationBarAnimator view controller, so let it manage navigation bar.
                
                self.transitionCoordinator?.animate(alongsideTransition: { (context) in
                    navigationController.navigationBar.tintColor = navigationBarAnimator.view.tintColor
                }, completion: { (context) in
                    if context.isCancelled
                    {
                        navigationController.navigationBar.tintColor = self.tintColor
                        
                        // Fix navigation bar tint color.
                        self._shouldResetLayout = true
                        self.view.setNeedsLayout()
                    }
                })
            }
            else
            {
                // Showing regular view controller, so show navigation bar.
                
                navigationController.navigationBar.barStyle = .default // Don't animate, or else status bar might appear messed-up.

                self.transitionCoordinator?.animate(alongsideTransition: { (context) in
                    self.showNavigationBar(for: navigationController)
                    navigationController.navigationBar.tintColor = topViewController.view.tintColor
                }, completion: { (context) in
                    if context.isCancelled
                    {
                        navigationController.navigationBar.tintColor = self.tintColor
                    }
                    else
                    {
                        self.showNavigationBar(for: navigationController)
                    }
                })
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        if self.navigationController == nil
        {
            self.resetNavigationBarAnimation()
        }
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if self._shouldResetLayout
        {
            // Various events can cause UI to mess up, so reset affected components now.
            
//            if self.navigationController?.topViewController == self
//            {
//                self.hideNavigationBar()
//            }
//
            self.prepareBlur()

            // Reset navigation bar animation, and create a new one later in this method if necessary.
            self.resetNavigationBarAnimation()
                        
            self._shouldResetLayout = false
        }
                
        let statusBarHeight = 20.0//self.view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        let cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
        
        let inset = 15 as CGFloat
        let padding = 20 as CGFloat
        
        let backButtonSize = self.backButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        var backButtonFrame = CGRect(x: inset, y: statusBarHeight,
                                     width: backButtonSize.width, height: backButtonSize.height)
        
        var headerFrame = CGRect(x: inset, y: 0, width: self.view.bounds.width - inset * 2, height: self.headerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        
        let backButtonPadding = 8.0
        let minimumHeaderY = backButtonFrame.maxY + backButtonPadding
        
        let minimumContentHeight = minimumHeaderY + headerFrame.height + padding // Minimum height for header + back button + spacing.
        let maximumContentY = max(self.view.bounds.width * 0.667, minimumContentHeight) // Initial Y-value of content view.
        
        // A full blur is too much, so we reduce the visible blur by 0.3, resulting in 70% blur.
        let minimumBlurFraction = 0.3 as CGFloat
        
        contentFrame.origin.y = maximumContentY - self.scrollView.contentOffset.y
        headerFrame.origin.y = contentFrame.origin.y - padding - headerFrame.height
        
        // Stretch the app icon image to fill additional vertical space if necessary.
        let height = max(contentFrame.origin.y + cornerRadius * 2, backgroundIconFrame.height)
        backgroundIconFrame.size.height = height
        
        let blurThreshold = 0 as CGFloat
        if self.scrollView.contentOffset.y < blurThreshold
        {
            // Determine how much to lessen blur by.
            
            let range = 75 as CGFloat
            let difference = -self.scrollView.contentOffset.y
            
            let fraction = min(difference, range) / range
            
            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            self.blurAnimator?.fractionComplete = fractionComplete
        }
        else
        {
            // Set blur to default.
            
            self.blurAnimator?.fractionComplete = minimumBlurFraction
        }
        
        // Animate navigation bar.
        let showNavigationBarThreshold = (maximumContentY - minimumContentHeight) + backButtonFrame.origin.y
        if self.scrollView.contentOffset.y > showNavigationBarThreshold
        {
            self.shouldHideNavigationBar = false
            
            if self.navigationBarAnimator == nil// && !self.isDisappearing
            {
                self.prepareNavigationBarAnimation()
            }
            
            let difference = self.scrollView.contentOffset.y - showNavigationBarThreshold
            let range = maximumContentY - (maximumContentY - padding - headerFrame.height) - inset
            
            let fractionComplete = min(difference, range) / range
            self.navigationBarAnimator?.fractionComplete = fractionComplete
        }
        else
        {
            self.shouldHideNavigationBar = true
            self.navigationBarAnimator?.fractionComplete = 0.0
//            self.resetNavigationBarAnimation()
        }
        
        let beginMovingBackButtonThreshold = (maximumContentY - minimumContentHeight)
        if self.scrollView.contentOffset.y > beginMovingBackButtonThreshold
        {
            let difference = self.scrollView.contentOffset.y - beginMovingBackButtonThreshold
            backButtonFrame.origin.y -= difference
        }
        
        let pinContentToTopThreshold = maximumContentY
        if self.scrollView.contentOffset.y > pinContentToTopThreshold
        {
            contentFrame.origin.y = 0
            backgroundIconFrame.origin.y = 0
            
            let difference = self.scrollView.contentOffset.y - pinContentToTopThreshold
            self.contentViewController.scrollView.contentOffset.y = difference
        }
        else
        {
            // Keep content table view's content offset at the top.
            self.contentViewController.scrollView.contentOffset.y = 0
        }

        // Keep background app icon centered in gap between top of content and top of screen.
        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2
        
        // Set frames.
        self.contentViewController.view.frame = contentFrame
        self.contentViewControllerShadowView.frame = self.contentViewController.view.frame
        self.backgroundImageView.frame = backgroundIconFrame
        
        self.backButton.frame = backButtonFrame
        self.backButton.layer.cornerRadius = self.backButton.bounds.midY
        
        // Adjust header scroll view content size for paging
        self.headerView.frame = CGRect(origin: .zero, size: headerFrame.size)
        self.headerScrollView.frame = headerFrame
        self.headerScrollView.contentSize = CGSize(width: headerFrame.width * 2, height: headerFrame.height)
        
        self.scrollView.verticalScrollIndicatorInsets.top = statusBarHeight
        self.headerScrollView.horizontalScrollIndicatorInsets.bottom = -12
        
        // Adjust content offset + size.
        let contentOffset = self.scrollView.contentOffset
        
        var contentSize = self.contentViewController.scrollView.contentSize
        contentSize.height += maximumContentY
        contentSize.height = max(contentSize.height, self.view.bounds.height + maximumContentY - (self.navigationController?.navigationBar.bounds.height ?? 0))
        self.scrollView.contentSize = contentSize
        
        self.scrollView.contentOffset = contentOffset
    }
    
    // Cannot add @objc functions in extensions of generic types, so include them in main definition instead.
    
    //MARK: Notifications
    
    @objc private func willEnterForeground(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
    
    @objc private func didBecomeActive(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        
        // Fixes Navigation Bar appearing after app becomes inactive -> active again.
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
    
    
    //MARK: UIAdaptivePresentationControllerDelegate
    
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool
    {
        return false
    }
    
    //MARK: UIScrollViewDelegate
    
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    {
        switch scrollView
        {
        case self.scrollView:
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            
        case self.headerScrollView:
            self.headerScrollView.showsHorizontalScrollIndicator = false
            
            let minimumBlurFraction = 0.3 as CGFloat
            
            let maximumX = self.headerScrollView.bounds.width
            let fraction = self.headerScrollView.contentOffset.x / maximumX
            
            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            self.blurAnimator?.fractionComplete = fractionComplete
            
        default: break
        }
    }
}

private extension HeaderContentViewController
{
    func update()
    {
        self.navigationController?.navigationBar.tintColor = self.tintColor
        self.backButton.tintColor = self.tintColor
    }
    
    func showNavigationBar(for navigationController: UINavigationController? = nil)
    {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.alpha = 1.0
        navigationController?.navigationBar.setNeedsLayout()
        
        if self.traitCollection.userInterfaceStyle == .dark
        {
            self._preferredStatusBarStyle = .lightContent
        }
        else
        {
            self._preferredStatusBarStyle = .default
        }
        
        navigationController?.setNeedsStatusBarAppearanceUpdate()
    }
    
    func hideNavigationBar(for navigationController: UINavigationController? = nil)
    {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.alpha = 0.0
        
        self._preferredStatusBarStyle = .lightContent
        navigationController?.setNeedsStatusBarAppearanceUpdate()
    }
    
    func prepareBlur()
    {
        if let animator = self.blurAnimator
        {
            animator.stopAnimation(true)
        }
        
        self.backgroundBlurView.effect = self._backgroundBlurEffect
        self.backgroundBlurView.contentView.backgroundColor = self._backgroundBlurTintColor
        
        self.blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.backgroundBlurView.effect = nil
            self?.backgroundBlurView.contentView.backgroundColor = .clear
        }

        self.blurAnimator?.startAnimation()
        self.blurAnimator?.pauseAnimation()
    }
    
    func prepareNavigationBarAnimation()
    {
        self.resetNavigationBarAnimation()
        
        let isNavBarHidden = self.shouldHideNavigationBar
        self.hideNavigationBar()
        
        self.navigationBarAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.showNavigationBar()
            self?.navigationController?.navigationBar.tintColor = self?.tintColor
            self?.navigationController?.navigationBar.barTintColor = nil
            self?.contentViewController.view.layer.cornerRadius = 0
        }
        self.navigationBarAnimator?.startAnimation()
        self.navigationBarAnimator?.pauseAnimation()
        
        if isNavBarHidden
        {
            self.hideNavigationBar()
        }
        else
        {
            self.showNavigationBar()
        }
        
        self.update()
    }
    
    func resetNavigationBarAnimation()
    {
//        guard _viewDidAppear else { return }
        
        self.navigationBarAnimator?.stopAnimation(true)
        self.navigationBarAnimator = nil
        
//        self.hideNavigationBar()
        
        self.contentViewController.view.layer.cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
    }
}
