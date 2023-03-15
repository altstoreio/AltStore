//
//  CarolineContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

extension Source
{
    var tintColor: UIColor? {
        return self.apps.first?.tintColor
    }
    
    var iconURL: URL? {
        return self.apps.first?.iconURL
    }
}

class DummyTableViewController: UITableViewController, CarolineContentViewController
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
        let dataSource = RSTArrayTableViewDataSource(items: ["Riley", "Shane", "Caroline", "Ryan", "Josh", "Evan", "Nicole"] as [NSString])
        dataSource.cellConfigurationHandler = { (cell, name, indexPath) in
            cell.textLabel?.text = name as String
        }
        
        return dataSource
    }
}

class ModernSourceDetailViewController: CarolineParentContentViewController
{
    let source: Source
    
    private var previousBounds: CGRect?
    
    private var addButton: UIButton!
    private var addButtonContainerView: UIView!
    
    init(source: Source)
    {
        self.source = source
        
        super.init()
    }
    
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.tintColor = self.source.tintColor
        
        self.navigationController?.navigationBar.tintColor = self.source.tintColor
        
        self.addButton = UIButton(type: .system)
        self.addButton.translatesAutoresizingMaskIntoConstraints = false
        self.addButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        self.addButton.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
        
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .secondaryLabel)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        vibrancyView.contentView.addSubview(self.addButton, pinningEdgesWith: .zero)
        blurView.contentView.addSubview(vibrancyView, pinningEdgesWith: .zero)
        self.addButtonContainerView = blurView

        self.contentView.addSubview(self.addButtonContainerView)
        
        self.navigationBarButton.setTitle("ADD", for: .normal)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.navigationBarButton)
        self.navigationBarButton.tintColor = self.source.tintColor
        
//        self.primaryOcculusionView = self.labelsStackView
        
//        let completedProgress = Progress(totalUnitCount: 1)
//        completedProgress.completedUnitCount = 1
//
//        self.addButton = PillButton(frame: .zero)
//        self.addButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
//        self.addButton.setTitle(NSLocalizedString("ADD", comment: ""), for: .normal)
//
//        var size = self.addButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
//        size.width = 72
//        self.addButton.frame.size = size
//
//        self.contentView.addSubview(self.addButton)
        
//        self.addButton.tintColor = self.source.tintColor
//        self.addButton.progressTintColor = .white
//        self.addButton.progress = completedProgress
//        self.addButton.isIndicatingActivity = false
//        self.addButton.isUserInteractionEnabled = true
        
//        self.addButton.progressTintColor = .red
        
        
        
//        let progress = Progress.discreteProgress(totalUnitCount: 10)
//        progress.completedUnitCount = 5
//
//        self.addButton.progress = progress
//        self.addButton.isIndicatingActivity = false
//        self.addButton.isUserInteractionEnabled = true
        
        
        
        
        Nuke.loadImage(with: self.source.iconURL, into: self.backgroundImageView)
        Nuke.loadImage(with: self.source.iconURL, into: self.navigationBarAppIconImageView)
        Nuke.loadImage(with: self.source.iconURL, into: self.headerImageView)
        
        self.navigationBarAppNameLabel.text = self.source.name
        self.navigationBarAppNameLabel.sizeToFit()
        
        let fittingSize = self.navigationBarTitleView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.navigationBarTitleView.frame.size = fittingSize
        
        self.navigationItem.titleView = nil
        self.navigationItem.titleView = self.navigationBarTitleView
        
        NSLayoutConstraint.activate([
            self.addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            self.addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 31)
        ])
        
        let addButtonSize = self.addButton.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.addButtonContainerView.frame.size = addButtonSize
        
        self.addButtonContainerView.clipsToBounds = true
        self.addButtonContainerView.layer.cornerRadius = self.addButtonContainerView.bounds.midY
    }
    
    override func update()
    {
        super.update()
        
//        for button in [self.navigationBarButton!]
//        {
//            button.tintColor = self.source.tintColor
//            button.isIndicatingActivity = false
//        }
        
        let barButtonItem = self.navigationItem.rightBarButtonItem
        self.navigationItem.rightBarButtonItem = nil
        self.navigationItem.rightBarButtonItem = barButtonItem
    }
    
    override func makeContentViewController() -> CarolineContentViewController
    {
        let contentViewController = SourcesDetailContentViewController(source: self.source)
        return contentViewController
    }
    
    override func makeHeaderContentView() -> UIView?
    {
        let sourceAboutView = SourceAboutView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
        return sourceAboutView
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let inset = 15.0
        
        self.addButtonContainerView.center.y = self.backButtonContainerView.center.y
        self.addButtonContainerView.frame.origin.x = self.view.bounds.width - inset - self.addButtonContainerView.bounds.width
        
        guard self.view.bounds != self.previousBounds else { return }
        self.previousBounds = self.view.bounds
                
        let headerSize = self.headerContentView.systemLayoutSizeFitting(CGSize(width: self.view.bounds.width - inset * 2, height: UIView.layoutFittingCompressedSize.height))
        self.headerContentView.frame.size.height = headerSize.height
    }
}

protocol CarolineContentViewController: UIViewController
{
    var scrollView: UIScrollView { get }
}

//extension CarolineContentViewController where Self: UITableViewController
//{
//    var scrollView: UIScrollView { self.tableView }
//}
//
//extension CarolineContentViewController where Self: UITableViewController
//{
//    var scrollView: UIScrollView { self.tableView }
//}

class CarolineParentContentViewController: UIViewController
{
    var primaryOcculusionView: UIView?
    
    private var contentViewController: CarolineContentViewController!
    private var contentViewControllerShadowView: UIView!
    
    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?
    
    private var contentSizeObservation: NSKeyValueObservation?
    
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private(set) var contentView: UIView!
    
//    @IBOutlet private var bannerView: AppBannerView!
    private(set) var headerContentView: UIView!
    @IBOutlet private(set) var headerImageView: UIImageView!
    
    @IBOutlet var labelsStackView: UIStackView!
    
    @IBOutlet private var backButton: UIButton!
    @IBOutlet private(set) var backButtonContainerView: UIVisualEffectView!
    
    @IBOutlet private(set) var backgroundImageView: UIImageView!
    @IBOutlet private var backgroundBlurView: UIVisualEffectView!
    
    @IBOutlet private(set) var navigationBarTitleView: UIView!
    @IBOutlet private(set) var navigationBarButton: PillButton!
    @IBOutlet private(set) var navigationBarAppIconImageView: UIImageView!
    @IBOutlet private(set) var navigationBarAppNameLabel: UILabel!
    
    private var _shouldResetLayout = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    
    private var _preferredStatusBarStyle: UIStatusBarStyle = .default
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return _preferredStatusBarStyle
    }
    
    init()
    {
        super.init(nibName: "CarolineParentContentViewController", bundle: .main)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func makeContentViewController() -> CarolineContentViewController
    {
        fatalError()
    }
    
    func makeHeaderContentView() -> UIView?
    {
        fatalError()
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
                        
        self.navigationBarTitleView.sizeToFit()
        self.navigationItem.titleView = self.navigationBarTitleView
        
        self.navigationController?.presentationController?.delegate = self
        
        self.headerContentView = self.makeHeaderContentView()
        self.headerContentView.translatesAutoresizingMaskIntoConstraints = true
        self.contentView.addSubview(self.headerContentView)
        
        self.contentViewController = self.makeContentViewController()
        
        self.addChild(self.contentViewController)
        self.contentViewController.view.frame = self.view.bounds
        self.contentView.addSubview(self.contentViewController.view)
        self.contentViewController.didMove(toParent: self)
        
        if #available(iOS 15, *)
        {
            // Fix navigation bar + tab bar appearance on iOS 15.
            self.setContentScrollView(self.scrollView)
            self.navigationItem.scrollEdgeAppearance = self.navigationController?.navigationBar.standardAppearance
        }
                
        self.contentViewControllerShadowView = UIView()
        self.contentViewControllerShadowView.backgroundColor = .white
        self.contentViewControllerShadowView.layer.cornerRadius = 38
        self.contentViewControllerShadowView.layer.shadowColor = UIColor.black.cgColor
        self.contentViewControllerShadowView.layer.shadowOffset = CGSize(width: 0, height: -1)
        self.contentViewControllerShadowView.layer.shadowRadius = 10
        self.contentViewControllerShadowView.layer.shadowOpacity = 0.3
        self.contentViewController.view.superview?.insertSubview(self.contentViewControllerShadowView, at: 0)
        
        self.contentView.addGestureRecognizer(self.scrollView.panGestureRecognizer)
        
        self.contentViewController.view.layer.cornerRadius = 38
        self.contentViewController.view.layer.masksToBounds = true
        
        self.contentViewController.scrollView.panGestureRecognizer.require(toFail: self.scrollView.panGestureRecognizer)
        self.contentViewController.scrollView.showsVerticalScrollIndicator = false
        
        // Bring to front so the scroll indicators are visible.
        self.view.bringSubviewToFront(self.scrollView)
        self.scrollView.isUserInteractionEnabled = false
        
        self.navigationBarAppNameLabel.text = self.title
        
        self.contentSizeObservation = self.contentViewController.scrollView.observe(\.contentSize, options: [.new, .old]) { [weak self] (scrollView, change) in
            
            guard let size = change.newValue, let previousSize = change.oldValue, size != previousSize else { return }
            print("[ALTLog] Content Size:", scrollView.contentSize)
            
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
        
        self.update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(CarolineParentContentViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CarolineParentContentViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        self._backgroundBlurEffect = self.backgroundBlurView.effect as? UIBlurEffect
        self._backgroundBlurTintColor = self.backgroundBlurView.contentView.backgroundColor
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        self.prepareBlur()
        
        // Update blur immediately.
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()

        self.transitionCoordinator?.animate(alongsideTransition: { (context) in
            self.hideNavigationBar()
        }, completion: nil)
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool)
    {
        super.viewWillDisappear(animated)

        // Guard against "dismissing" when presenting via 3D Touch pop.
        guard self.navigationController != nil else { return }

        // Store reference since self.navigationController will be nil after disappearing.
        let navigationController = self.navigationController
        navigationController?.navigationBar.barStyle = .default // Don't animate, or else status bar might appear messed-up.

        self.transitionCoordinator?.animate(alongsideTransition: { (context) in
            self.showNavigationBar(for: navigationController)
        }, completion: { (context) in
            if !context.isCancelled
            {
                self.showNavigationBar(for: navigationController)
            }
        })
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        if self.navigationController == nil
        {
            self.resetNavigationBarAnimation()
        }
    }
    
//    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
//    {
//        guard segue.identifier == "embedAppContentViewController" else { return }
//        
//        self.contentViewController = segue.destination as? AppContentViewController
//        self.contentViewController.app = self.app
//        
//        if #available(iOS 15, *)
//        {
//            // Fix navigation bar + tab bar appearance on iOS 15.
//            self.setContentScrollView(self.scrollView)
//            self.navigationItem.scrollEdgeAppearance = self.navigationController?.navigationBar.standardAppearance
//        }
//    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.navigationController?.navigationBar.tintColor = self.view.tintColor
        self.backButtonContainerView.tintColor = self.view.tintColor
        self.navigationBarButton.tintColor = self.view.tintColor
        self.navigationBarAppIconImageView.tintColor = self.view.tintColor
        
        if self._shouldResetLayout
        {
            // Various events can cause UI to mess up, so reset affected components now.
            
            if self.navigationController?.topViewController == self
            {
                self.hideNavigationBar()
            }
            
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
                                     width: backButtonSize.width + 20, height: backButtonSize.height + 20)
        
        var headerFrame = CGRect(x: inset, y: 0, width: self.view.bounds.width - inset * 2, height: self.headerContentView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        
        let backButtonPadding = 8.0
        let minimumHeaderY = backButtonFrame.maxY + backButtonPadding
        
        let occlusionView = self.primaryOcculusionView ?? self.headerContentView!
        let localOcclusionFrame = self.headerContentView.convert(occlusionView.frame, from: occlusionView.superview)
        let occlusionFrame = self.contentView.convert(occlusionView.frame, from: occlusionView.superview)
        
        
        
//        let minimumContentY = minimumHeaderY + (headerFrame.height - localOcclusionFrame.minY) + padding // Y-value at point we start showing nav bar
        let minimumContentY = minimumHeaderY + headerFrame.height + padding // Y-value at point we start showing nav bar
        let maximumContentY = max(self.view.bounds.width * 0.667, minimumHeaderY + headerFrame.height + padding) // Initial Y-value of content view
        
        
        
        // 204 =
        
//        print("[ALTLog] Min: \(minimumContentY). Max: \(maximumContentY). Difference: \(maximumContentY - minimumContentY)")
        
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
        let showNavigationBarThreshold = (maximumContentY - minimumContentY) + backButtonFrame.origin.y
        if self.scrollView.contentOffset.y > showNavigationBarThreshold
        {
            if self.navigationBarAnimator == nil
            {
                self.prepareNavigationBarAnimation()
            }
            
            let difference = self.scrollView.contentOffset.y - showNavigationBarThreshold
            
            // Range = (MAX Y OF VISIBLE OCCULUSION VIEW - HEIGHT OF OCCLUSION)
            
            
//            let range2 = maximumContentY - (maximumContentY - padding - (headerFrame.height - localOcclusionFrame.minY)) - inset
            let range2 = maximumContentY - (maximumContentY - padding - headerFrame.height) - inset
            
            let range = contentFrame.minY - occlusionFrame.minY  // - (self.navigationController?.navigationBar.bounds.height ?? self.view.safeAreaInsets.top)
//            print("[ALTLog] Difference: \(difference). Range: \(range2). ContentY: \(contentFrame.minY) OcclusionY: \(occlusionFrame.minY)")
            
            let fractionComplete = min(difference, range2) / range2
            self.navigationBarAnimator?.fractionComplete = fractionComplete
            
//            print("[ALTLog] Difference: \(difference). Range: \(range). Fraction: \(fractionComplete)")
        }
        else
        {
            self.resetNavigationBarAnimation()
        }
        
        let beginMovingBackButtonThreshold = (maximumContentY - minimumContentY)
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
//        self.contentViewController.view.superview?.frame = contentFrame
        self.contentViewController.view.frame = contentFrame
        self.headerContentView.frame = headerFrame
        self.backgroundImageView.frame = backgroundIconFrame
        self.backgroundBlurView.frame = backgroundIconFrame
        self.backButtonContainerView.frame = backButtonFrame
        
//        print("[ALTLog] Header Frame:", headerFrame)
        
        self.contentViewControllerShadowView.frame = self.contentViewController.view.frame
        
        self.backButtonContainerView.layer.cornerRadius = self.backButtonContainerView.bounds.midY
        
        self.scrollView.verticalScrollIndicatorInsets.top = statusBarHeight
        
        // Adjust content offset + size.
        let contentOffset = self.scrollView.contentOffset
        
        var contentSize = self.contentViewController.scrollView.contentSize
        contentSize.height += maximumContentY
        contentSize.height = max(contentSize.height, self.view.bounds.height + maximumContentY - (self.navigationController?.navigationBar.bounds.height ?? 0))
        
//        print("[RSTLog] ContentSize:", contentSize, self.view.bounds.height, maximumContentY, self.navigationController?.navigationBar.bounds.height ?? 0)
        
        self.scrollView.contentSize = contentSize
        self.scrollView.contentOffset = contentOffset
        
//        print("[ALTLog] Content Y:", self.scrollView.contentOffset.y, contentSize.height - self.view.bounds.height)
        
//
//        self.bannerView.backgroundEffectView.backgroundColor = .clear
    }
    
    func update()
    {
        // Override
    }
    
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
}

extension CarolineParentContentViewController
{
//    class func makeAppViewController(app: StoreApp) -> AppViewController
//    {
//        let storyboard = UIStoryboard(name: "Main", bundle: nil)
//
//        let appViewController = storyboard.instantiateViewController(withIdentifier: "appViewController") as! AppViewController
//        appViewController.app = app
//        return appViewController
//    }
}

private extension CarolineParentContentViewController
{
    func showNavigationBar(for navigationController: UINavigationController? = nil)
    {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.alpha = 1.0
        navigationController?.navigationBar.tintColor = .altPrimary
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
        
        self.navigationBarAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.showNavigationBar()
            self?.navigationController?.navigationBar.tintColor = self?.view.tintColor
            self?.navigationController?.navigationBar.barTintColor = nil
            self?.contentViewController.view.layer.cornerRadius = 0
        }
        
        self.navigationBarAnimator?.startAnimation()
        self.navigationBarAnimator?.pauseAnimation()
        
        self.update()
    }
    
    func resetNavigationBarAnimation()
    {
        self.navigationBarAnimator?.stopAnimation(true)
        self.navigationBarAnimator = nil
        
        self.hideNavigationBar()
        
        self.contentViewController.view.layer.cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
    }
}

private extension CarolineParentContentViewController
{
    @IBAction func popViewController(_ sender: UIButton)
    {
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc func willEnterForeground(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
    
    @objc func didBecomeActive(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        
        // Fixes Navigation Bar appearing after app becomes inactive -> active again.
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
    }
}

extension CarolineParentContentViewController: UIScrollViewDelegate
{
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    {
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        
//        print("[ALTLog] ContentY:", scrollView.contentOffset.y)
    }
}

extension CarolineParentContentViewController: UIAdaptivePresentationControllerDelegate
{
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool
    {
        return false
    }
}
