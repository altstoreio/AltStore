//
//  HeaderContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/10/23.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

protocol ScrollableContentViewController: UIViewController
{
    var scrollView: UIScrollView { get }
}

class HeaderContentViewController<Header: UIView, Content: ScrollableContentViewController> : UIViewController,
                                                                                              UIAdaptivePresentationControllerDelegate,
                                                                                              UIScrollViewDelegate,
                                                                                              UIGestureRecognizerDelegate
{
    var tintColor: UIColor? {
        didSet {
            guard self.isViewLoaded else { return }
            
            self.view.tintColor = self.tintColor?.adjustedForDisplay
            self.update()
        }
    }
    
    private(set) var headerView: Header!
    private(set) var contentViewController: Content!
    
    private(set) var backButton: VibrantButton!
    private(set) var backgroundImageView: UIImageView!
    
    private(set) var navigationBarNameLabel: UILabel!
    private(set) var navigationBarIconView: UIImageView!
    private(set) var navigationBarTitleView: UIStackView!
    private(set) var navigationBarButton: PillButton!
    
    private var scrollView: UIScrollView!
    private var headerScrollView: UIScrollView!
    private var headerContainerView: UIView!
    private var backgroundBlurView: UIVisualEffectView!
    private var contentViewControllerShadowView: UIView!
    
    private var ignoreBackGestureRecognizer: UIPanGestureRecognizer!
    
    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?
    private var contentSizeObservation: NSKeyValueObservation?
    
    private var _shouldResetLayout = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    
    private var isViewingHeader: Bool {
        let isViewingHeader = (self.headerScrollView.contentOffset.x != self.headerScrollView.contentInset.left)
        return isViewingHeader
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 17, *)
        {
            // On iOS 17+, .default will update the status bar automatically.
            return .default
        }
        else
        {
            return _preferredStatusBarStyle
        }
    }
    private var _preferredStatusBarStyle: UIStatusBarStyle = .default
    
    init()
    {
        super.init(nibName: nil, bundle: nil)
    }
    
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
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
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.view.addSubview(self.backgroundImageView)
        
        let blurEffect = UIBlurEffect(style: .regular)
        self.backgroundBlurView = UIVisualEffectView(effect: blurEffect)
        self.view.addSubview(self.backgroundBlurView, pinningEdgesWith: .zero)
                
        
        // Header View
        self.headerContainerView = UIView(frame: .zero)
        self.view.addSubview(self.headerContainerView, pinningEdgesWith: .zero)
        
        self.ignoreBackGestureRecognizer = UIPanGestureRecognizer(target: self, action: nil)
        self.ignoreBackGestureRecognizer.delegate = self
        self.headerContainerView.addGestureRecognizer(self.ignoreBackGestureRecognizer)
        self.navigationController?.interactivePopGestureRecognizer?.require(toFail: self.ignoreBackGestureRecognizer) // So we can disable back gesture when viewing header.
        
        self.headerScrollView = UIScrollView(frame: .zero)
        self.headerScrollView.delegate = self
        self.headerScrollView.isPagingEnabled = true
        self.headerScrollView.clipsToBounds = false
        self.headerScrollView.indicatorStyle = .white
        self.headerScrollView.showsVerticalScrollIndicator = false
        self.headerContainerView.addSubview(self.headerScrollView)
        self.headerContainerView.addGestureRecognizer(self.headerScrollView.panGestureRecognizer) // Allow panning outside headerScrollView bounds.
        
        self.headerView = self.makeHeaderView()
        self.headerScrollView.addSubview(self.headerView)
        
        let imageConfiguration = UIImage.SymbolConfiguration(weight: .semibold)
        let image = UIImage(systemName: "chevron.backward", withConfiguration: imageConfiguration)
        
        self.backButton = VibrantButton(type: .system)
        self.backButton.image = image
        self.backButton.tintColor = self.tintColor
        self.backButton.sizeToFit()
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
                
        // Add scrollView to front so the scroll indicators are visible, but disable user interaction.
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
        self.navigationBarIconView.clipsToBounds = true
        
        self.navigationBarTitleView = UIStackView(arrangedSubviews: [self.navigationBarIconView, self.navigationBarNameLabel])
        self.navigationBarTitleView.axis = .horizontal
        self.navigationBarTitleView.spacing = 8
        
        self.navigationBarButton = PillButton(type: .system)
        self.navigationBarButton.setContentCompressionResistancePriority(UILayoutPriority(rawValue: 9000), for: .horizontal) // Prioritize over title length.
        
        // Embed navigationBarButton in container view with Auto Layout to ensure it can automatically update its size.
        let buttonContainerView = UIView()
        buttonContainerView.addSubview(self.navigationBarButton, pinningEdgesWith: .zero)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: buttonContainerView)
        
        NSLayoutConstraint.activate([
            self.navigationBarIconView.widthAnchor.constraint(equalToConstant: 35),
            self.navigationBarIconView.heightAnchor.constraint(equalTo: self.navigationBarIconView.widthAnchor)
        ])
                
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
        
        // Don't call update() before subclasses have finished viewDidLoad().
        // self.update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HeaderContentViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        if #available(iOS 15, *)
        {
            // Fix navigation bar + tab bar appearance on iOS 15.
            self.setContentScrollView(self.scrollView)
        }
        
        // Start with navigation bar hidden.
        self.hideNavigationBar()
        
        self.view.tintColor = self.tintColor?.adjustedForDisplay
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.prepareBlur()
        
        // Update blur immediately.
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        
        self.headerScrollView.flashScrollIndicators()
        
        self.update()
    }
    
    override func viewIsAppearing(_ animated: Bool) 
    {
        super.viewIsAppearing(animated)
        
        // Ensure header view has correct layout dimensions.
        self.headerView.setNeedsLayout()
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if self._shouldResetLayout
        {
            // Various events can cause UI to mess up, so reset affected components now.
            
            self.prepareBlur()

            // Reset navigation bar animation, and create a new one later in this method if necessary.
            self.resetNavigationBarAnimation()
                        
            self._shouldResetLayout = false
        }
        
        let statusBarHeight: Double
        
        if let navigationController, navigationController.presentingViewController != nil, navigationController.modalPresentationStyle != .fullScreen
        {
            statusBarHeight = 20
        }
        else if let statusBarManager = (self.view.window ?? self.presentedViewController?.view.window)?.windowScene?.statusBarManager
        {
            statusBarHeight = statusBarManager.statusBarFrame.height
        }
        else
        {
            statusBarHeight = 0
        }
        
        let cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
        
        let inset = 15 as CGFloat
        let padding = 20 as CGFloat
        
        let backButtonSize = self.backButton.sizeThatFits(CGSize(width: Double.infinity, height: .infinity))
        let largestBackButtonDimension = max(backButtonSize.width, backButtonSize.height) // Enforce 1:1 aspect ratio.
        var backButtonFrame = CGRect(x: inset, y: statusBarHeight, width: largestBackButtonDimension, height: largestBackButtonDimension)
        
        var headerFrame = CGRect(x: inset, y: 0, width: self.view.bounds.width - inset * 2, height: self.headerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        
        let backButtonPadding = 8.0
        let minimumHeaderY = backButtonFrame.maxY + backButtonPadding
        
        let minimumContentHeight = minimumHeaderY + headerFrame.height + padding // Minimum height for header + back button + spacing.
        let maximumContentY = max(self.view.bounds.width * 0.667, minimumContentHeight) // Initial Y-value of content view.
        
        contentFrame.origin.y = maximumContentY - self.scrollView.contentOffset.y
        headerFrame.origin.y = contentFrame.origin.y - padding - headerFrame.height
        
        // Stretch the app icon image to fill additional vertical space if necessary.
        let height = max(contentFrame.origin.y + cornerRadius * 2, backgroundIconFrame.height)
        backgroundIconFrame.size.height = height
        
        // Update blur.
        self.updateBlur()
        
        // Animate navigation bar.
        let showNavigationBarThreshold = (maximumContentY - minimumContentHeight) + backButtonFrame.origin.y
        if self.scrollView.contentOffset.y > showNavigationBarThreshold
        {
            if self.navigationBarAnimator == nil
            {
                self.prepareNavigationBarAnimation()
            }
            
            let difference = self.scrollView.contentOffset.y - showNavigationBarThreshold
            
            let range: Double
            if self.presentingViewController == nil && self.parent?.presentingViewController == nil
            {
                // Not presented modally, so rely on safe area + navigation bar height.
                range = (headerFrame.height + padding) - (self.navigationController?.navigationBar.bounds.height ?? self.view.safeAreaInsets.top)
            }
            else
            {
                // Presented modally, so rely on maximumContentY.
                range = maximumContentY - (maximumContentY - padding - headerFrame.height) - inset
            }
            
            let fractionComplete = min(difference, range) / range
            self.navigationBarAnimator?.fractionComplete = fractionComplete
        }
        else
        {
            self.navigationBarAnimator?.fractionComplete = 0.0
            self.resetNavigationBarAnimation()
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
            self.contentViewController.scrollView.contentOffset.y = -self.contentViewController.scrollView.contentInset.top + difference
        }
        else
        {
            // Keep content table view's content offset at the top.
            self.contentViewController.scrollView.contentOffset.y = -self.contentViewController.scrollView.contentInset.top
        }

        // Keep background app icon centered in gap between top of content and top of screen.
        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2
        
        // Set frames.
        self.contentViewController.view.frame = contentFrame
        self.contentViewControllerShadowView.frame = contentFrame
        self.backgroundImageView.frame = backgroundIconFrame
        
        self.backButton.frame = backButtonFrame
        self.backButton.layer.cornerRadius = backButtonFrame.height / 2
        
        // Adjust header scroll view content size for paging
        self.headerView.frame = CGRect(origin: .zero, size: headerFrame.size)
        self.headerScrollView.frame = headerFrame
        self.headerScrollView.contentSize = CGSize(width: headerFrame.width * 2, height: headerFrame.height)
        
        self.scrollView.verticalScrollIndicatorInsets.top = statusBarHeight
        self.headerScrollView.horizontalScrollIndicatorInsets.bottom = -12
        
        // Adjust content offset + size.
        let contentOffset = self.scrollView.contentOffset
        
        var contentSize = self.contentViewController.scrollView.contentSize
        contentSize.height += self.contentViewController.scrollView.contentInset.top + self.contentViewController.scrollView.contentInset.bottom
        contentSize.height += maximumContentY
        contentSize.height = max(contentSize.height, self.view.bounds.height + maximumContentY - (self.navigationController?.navigationBar.bounds.height ?? 0))
        self.scrollView.contentSize = contentSize
        
        self.scrollView.contentOffset = contentOffset
    }
    
    func update()
    {
        // Overridden by subclasses.
    }
    
    /// Cannot add @objc functions in extensions of generic types, so include them in main definition instead.
    
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
        
        // Fixes incorrect blur after app becomes inactive -> active again.
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
        case self.scrollView: self.view.setNeedsLayout()
        case self.headerScrollView:
            // Do NOT call setNeedsLayout(), or else it will mess with scrolling.
            self.headerScrollView.showsHorizontalScrollIndicator = false
            self.updateBlur()
            
        default: break
        }
    }
    
    //MARK: UIGestureRecognizerDelegate
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    {
        // Ignore interactive back gesture when viewing header, which means returning `true` to enable ignoreBackGestureRecognizer.
        let disableBackGesture = self.isViewingHeader
        return disableBackGesture
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return true
    }
}

private extension HeaderContentViewController
{
    func showNavigationBar()
    {
        self.navigationBarIconView.alpha = 1.0
        self.navigationBarNameLabel.alpha = 1.0
        self.navigationBarButton.alpha = 1.0
        
        self.updateNavigationBarAppearance(isHidden: false)
        
        if self.traitCollection.userInterfaceStyle == .dark
        {
            self._preferredStatusBarStyle = .lightContent
        }
        else
        {
            self._preferredStatusBarStyle = .default
        }
        
        if #unavailable(iOS 17)
        {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    func hideNavigationBar()
    {
        self.navigationBarIconView.alpha = 0.0
        self.navigationBarNameLabel.alpha = 0.0
        self.navigationBarButton.alpha = 0.0
        
        self.updateNavigationBarAppearance(isHidden: true)
        
        self._preferredStatusBarStyle = .lightContent
        
        if #unavailable(iOS 17)
        {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    func updateNavigationBarAppearance(isHidden: Bool)
    {
        let barAppearance = self.navigationItem.standardAppearance as? NavigationBarAppearance ?? NavigationBarAppearance()
        
        if isHidden
        {
            barAppearance.configureWithTransparentBackground()
            barAppearance.ignoresUserInteraction = true
        }
        else
        {
            barAppearance.configureWithDefaultBackground()
            barAppearance.ignoresUserInteraction = false
        }
        
        barAppearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
        
        let dynamicColor = UIColor { traitCollection in
            var tintColor = self.tintColor ?? .altPrimary
            
            if traitCollection.userInterfaceStyle == .dark && tintColor.isTooDark
            {
                tintColor = .white
            }
            else
            {
                tintColor = tintColor.adjustedForDisplay
            }
            
            return tintColor
        }
        
        let tintColor = isHidden ? UIColor.clear : dynamicColor
        barAppearance.configureWithTintColor(tintColor)
        
        self.navigationItem.standardAppearance = barAppearance
        self.navigationItem.scrollEdgeAppearance = barAppearance
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
    
    func updateBlur()
    {
        // A full blur is too much for header, so we reduce the visible blur by 0.3, resulting in 70% blur.
        let minimumBlurFraction = 0.3 as CGFloat
        
        if self.isViewingHeader
        {
            let maximumX = self.headerScrollView.bounds.width
            let fraction = self.headerScrollView.contentOffset.x / maximumX
            
            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            self.blurAnimator?.fractionComplete = fractionComplete
        }
        else if self.scrollView.contentOffset.y < 0
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
    }
    
    func prepareNavigationBarAnimation()
    {
        self.resetNavigationBarAnimation()
        
        self.navigationBarAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.showNavigationBar()
            
            // Must call layoutIfNeeded() to animate appearance change.
            self?.navigationController?.navigationBar.layoutIfNeeded()
            
            self?.contentViewController.view.layer.cornerRadius = 0
        }
        self.navigationBarAnimator?.startAnimation()
        self.navigationBarAnimator?.pauseAnimation()
        
        self.update()
    }
    
    func resetNavigationBarAnimation()
    {
        guard self.navigationBarAnimator != nil else { return }
        
        self.navigationBarAnimator?.stopAnimation(true)
        self.navigationBarAnimator = nil
        
        self.hideNavigationBar()
        
        self.contentViewController.view.layer.cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
    }
}
