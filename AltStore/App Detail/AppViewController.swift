//
//  AppViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltStoreCore
import Roxas

import Nuke
import NukeExtensions

class AppViewController: UIViewController
{
    var app: StoreApp!
    
    private var contentViewController: AppContentViewController!
    private var contentViewControllerShadowView: UIView!
    
    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?
    
    private var contentSizeObservation: NSKeyValueObservation?
    
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentView: UIView!
    
    @IBOutlet private var bannerView: AppBannerView!
    
    @IBOutlet private var backButton: UIButton!
    @IBOutlet private var backButtonContainerView: UIVisualEffectView!
    
    @IBOutlet private var backgroundAppIconImageView: UIImageView!
    @IBOutlet private var backgroundBlurView: UIVisualEffectView!
    
    @IBOutlet private var navigationBarTitleView: UIView!
    @IBOutlet private var navigationBarDownloadButton: PillButton!
    @IBOutlet private var navigationBarAppIconImageView: UIImageView!
    @IBOutlet private var navigationBarAppNameLabel: UILabel!
    
    private var likesButton: UIButton!
    private var moreButton: UIButton!
    
    private var likesButtonContainerView: UIVisualEffectView!
    private var moreButtonContainerView: UIVisualEffectView!
    
    private var _shouldResetLayout = false
    private var previousLayoutBounds: CGRect?
    private var previousSafeAreaInsets: UIEdgeInsets?
    private var _viewDidAppear = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    
    private var _isLiked: Bool = false
    private var _likesCount: Int = 0
    
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    private var _preferredStatusBarStyle: UIStatusBarStyle = .default
    
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
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
                        
        self.navigationBarTitleView.sizeToFit()
        self.navigationItem.titleView = self.navigationBarTitleView
        
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
        
        self.contentViewController.tableView.panGestureRecognizer.require(toFail: self.scrollView.panGestureRecognizer)
        self.contentViewController.appDetailCollectionViewController.collectionView.panGestureRecognizer.require(toFail: self.scrollView.panGestureRecognizer)
        self.contentViewController.tableView.showsVerticalScrollIndicator = false
        
        // Bring to front so the scroll indicators are visible.
        self.view.bringSubviewToFront(self.scrollView)
        self.scrollView.isUserInteractionEnabled = false
        
        self.bannerView.frame = CGRect(x: 0, y: 0, width: 300, height: 93)
        self.bannerView.backgroundEffectView.effect = UIBlurEffect(style: .regular)
        self.bannerView.backgroundEffectView.backgroundColor = .clear
        self.bannerView.iconImageView.image = nil
        self.bannerView.iconImageView.tintColor = self.app.tintColor
        self.bannerView.button.tintColor = self.app.tintColor
        self.bannerView.tintColor = self.app.tintColor
        self.bannerView.accessibilityTraits.remove(.button)
        
        self.bannerView.button.addTarget(self, action: #selector(AppViewController.performAppAction(_:)), for: .primaryActionTriggered)
        
        self.backButtonContainerView.tintColor = self.app.tintColor
        
        self.navigationBarDownloadButton.tintColor = self.app.tintColor
        self.navigationBarAppNameLabel.text = self.app.name
        self.navigationBarAppIconImageView.tintColor = self.app.tintColor
        
        self.contentSizeObservation = self.contentViewController.tableView.observe(\.contentSize) { [weak self] (tableView, change) in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
        
        // Set before update()
        self._likesCount = Int(self.app.federatedItem?.likesCount ?? 0)
        self._isLiked = self.app.federatedItem?.isLiked ?? false
        
        self.prepareSocialButtons()
        self.update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.didChangeApp(_:)), name: .NSManagedObjectContextObjectsDidChange, object: DatabaseManager.shared.viewContext)
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        self._backgroundBlurEffect = self.backgroundBlurView.effect as? UIBlurEffect
        self._backgroundBlurTintColor = self.backgroundBlurView.contentView.backgroundColor
        
        // Load Images
        for imageView in [self.bannerView.iconImageView!, self.backgroundAppIconImageView!, self.navigationBarAppIconImageView!]
        {
            imageView.isIndicatingActivity = true
            
            NukeExtensions.loadImage(with: self.app.iconURL, options: .shared, into: imageView, progress: nil) { [weak imageView] (result) in
                switch result
                {
                case .success:
                    imageView?.isIndicatingActivity = false
                    imageView?.backgroundColor = .clear
                    
                case .failure(let error): print("[ALTLog] Failed to load app icons.", error)
                }
            }
        }
        
        // Start with navigation bar hidden.
        self.hideNavigationBar()
        
        if #available(iOS 26, *)
        {
            if let downloadButton = self.navigationItem.rightBarButtonItem
            {
                downloadButton.style = .prominent
                downloadButton.tintColor = self.app.tintColor
            }
            
            self.backButton.isHidden = true
            self.backButtonContainerView.isHidden = true
        }
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        self.prepareBlur()
        
        // Update blur immediately.
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    override func viewIsAppearing(_ animated: Bool)
    {
        super.viewIsAppearing(animated)
        
        // Prevent banner temporarily flashing a color due to being added back to self.view.
        self.bannerView.backgroundEffectView.backgroundColor = .clear
        
        self.updateFediverseInteractions()
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        self._viewDidAppear = true
        
        self._shouldResetLayout = true
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        if self.navigationController == nil
        {
            self.resetNavigationBarAnimation()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "embedAppContentViewController" else { return }
        
        self.contentViewController = segue.destination as? AppContentViewController
        self.contentViewController.app = self.app
        
        if #available(iOS 15, *)
        {
            // Fix navigation bar + tab bar appearance on iOS 15.
            self.setContentScrollView(self.scrollView)
        }
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if self.previousLayoutBounds != self.view.bounds || self.previousSafeAreaInsets != self.view.safeAreaInsets
        {
            self.previousLayoutBounds = self.view.bounds
            self.previousSafeAreaInsets = self.view.safeAreaInsets
            self._shouldResetLayout = true
        }

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
        else if let window = self.view.window ?? self.presentedViewController?.view.window
        {
            // The status bar can be vertical on iPhone Duo. Its height is not a top inset.
            let safeAreaFrame = self.view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
            statusBarHeight = max(0, safeAreaFrame.minY - self.view.bounds.minY)
        }
        else
        {
            statusBarHeight = 0
        }
        
        // Only the top overlap affects vertical scrolling when navigation bars move to the side.
        let navigationBarHeight = max(0, self.view.safeAreaInsets.top - statusBarHeight)
        let cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
        
        // Keep custom controls clear of side-mounted bars and display cutouts.
        let safeAreaFrame = self.view.safeAreaLayoutGuide.layoutFrame
        let inset = 12 as CGFloat
        let padding = 20 as CGFloat
        
        let backButtonSize = self.backButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        var backButtonFrame = CGRect(x: safeAreaFrame.minX + inset, y: statusBarHeight,
                                     width: backButtonSize.width + 20, height: backButtonSize.height + 20)
        
        let moreButtonSize = self.moreButton.bounds.size
        var moreButtonFrame = CGRect(x: safeAreaFrame.maxX - inset - moreButtonSize.width, y: statusBarHeight,
                                     width: moreButtonSize.width, height: moreButtonSize.height)
        
        let likesButtonSize = self.likesButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        var likesButtonFrame = CGRect(x: safeAreaFrame.maxX - inset - moreButtonSize.width - inset - likesButtonSize.width, y: statusBarHeight,
                                      width: likesButtonSize.width, height: likesButtonSize.height)
        
        var headerFrame = CGRect(x: safeAreaFrame.minX + inset, y: 0, width: max(0, safeAreaFrame.width - inset * 2), height: self.bannerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        
        let minimumHeaderY = backButtonFrame.maxY + 8
        
        let minimumContentY = minimumHeaderY + headerFrame.height + padding
        // A wide, short window should not push the app's content below the fold.
        let maximumContentY = max(minimumContentY, min(safeAreaFrame.width, safeAreaFrame.height) * 0.667)
        
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
            
            let range: Double
            if self.presentingViewController == nil && self.parent?.presentingViewController == nil
            {
                // Not presented modally, so rely on safe area + navigation bar height.
                range = max(1, headerFrame.height + padding - navigationBarHeight)
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
        
        let beginMovingBackButtonThreshold = (maximumContentY - minimumContentY)
        if self.scrollView.contentOffset.y > beginMovingBackButtonThreshold
        {
            let difference = self.scrollView.contentOffset.y - beginMovingBackButtonThreshold
            backButtonFrame.origin.y -= difference
            moreButtonFrame.origin.y -= difference
            likesButtonFrame.origin.y -= difference
        }
        
        let pinContentToTopThreshold = maximumContentY
        if self.scrollView.contentOffset.y > pinContentToTopThreshold
        {
            contentFrame.origin.y = 0
            backgroundIconFrame.origin.y = 0
            
            let difference = self.scrollView.contentOffset.y - pinContentToTopThreshold
            self.contentViewController.tableView.contentOffset.y = difference
        }
        else
        {
            // Keep content table view's content offset at the top.
            self.contentViewController.tableView.contentOffset.y = 0
        }

        // Keep background app icon centered in gap between top of content and top of screen.
        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2
        
        // Set frames.
        self.contentViewController.view.superview?.frame = contentFrame
        self.bannerView.frame = headerFrame
        self.backgroundAppIconImageView.frame = backgroundIconFrame
        self.backgroundBlurView.frame = backgroundIconFrame
        self.backButtonContainerView.frame = backButtonFrame
        
        self.moreButton.frame = CGRect(origin: .zero, size: moreButtonSize)
        self.moreButtonContainerView.frame = moreButtonFrame
        
        self.likesButton.frame = CGRect(origin: .zero, size: likesButtonSize)
        self.likesButtonContainerView.frame = likesButtonFrame
        
        self.contentViewControllerShadowView.frame = self.contentViewController.view.frame
        
        self.backButtonContainerView.layer.cornerRadius = self.backButtonContainerView.bounds.midY
        
        self.likesButtonContainerView.layer.cornerRadius = self.likesButtonContainerView.bounds.height / 2
        self.moreButtonContainerView.layer.cornerRadius = self.moreButtonContainerView.bounds.height / 2
        
        self.scrollView.verticalScrollIndicatorInsets.top = statusBarHeight
        
        // Adjust content offset + size.
        let contentOffset = self.scrollView.contentOffset
        
        var contentSize = self.contentViewController.tableView.contentSize
        contentSize.height += maximumContentY
        
        self.scrollView.contentSize = contentSize
        self.scrollView.contentOffset = contentOffset
        
        self.bannerView.backgroundEffectView.backgroundColor = .clear
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if self._viewDidAppear
        {
            self._shouldResetLayout = true
        }
    }
    
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
}

extension AppViewController
{
    class func makeAppViewController(app: StoreApp) -> AppViewController
    {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let appViewController = storyboard.instantiateViewController(withIdentifier: "appViewController") as! AppViewController
        appViewController.app = app
        return appViewController
    }
}

private extension AppViewController
{
    func update()
    {
        var buttonAction: AppBannerView.AppAction?
        
        if let installedApp = self.app.installedApp, let latestVersion = self.app.latestAvailableVersion, !installedApp.matches(latestVersion), !self.app.isPledgeRequired || self.app.isPledged
        {
            // Explicitly set button action to .update if there is an update available, even if it's not supported.
            buttonAction = .update(installedApp)
        }
        
        for button in [self.bannerView.button!, self.navigationBarDownloadButton!]
        {
            if #unavailable(iOS 26)
            {
                button.tintColor = self.app.tintColor
            }
            button.isIndicatingActivity = false
        }
        
        self.bannerView.configure(for: self.app, action: buttonAction)
        
        let title = self.bannerView.button.title(for: .normal)
        self.navigationBarDownloadButton.setTitle(title, for: .normal)
        self.navigationBarDownloadButton.progress = self.bannerView.button.progress
        self.navigationBarDownloadButton.countdownDate = self.bannerView.button.countdownDate
        
        let barButtonItem = self.navigationItem.rightBarButtonItem
        self.navigationItem.rightBarButtonItem = nil
        self.navigationItem.rightBarButtonItem = barButtonItem
        
        if self._likesCount > 0
        {
            self.likesButton.configuration?.title = String(self._likesCount)
            self.likesButton.accessibilityLabel = String(AttributedString(localized: "^[\(self._likesCount) like](inflect: true)").characters)
            self.likesButton.accessibilityValue = self._isLiked ? String(localized: "Liked") : nil
        }
        else
        {
            self.likesButton.configuration?.title = nil
            self.likesButton.accessibilityLabel = self._isLiked ? String(localized: "Unlike") : String(localized: "Like")
            self.likesButton.accessibilityValue = nil
        }
        
        self.likesButton.accessibilityHint = self._isLiked ? String(localized: "Unlikes this app") : String(localized: "Likes this app")
        
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 17.0, weight: .semibold)
        if self._isLiked
        {
            self.likesButton.configuration?.image = UIImage(systemName: "heart.fill", withConfiguration: imageConfig)
        }
        else
        {
            self.likesButton.configuration?.image = UIImage(systemName: "heart", withConfiguration: imageConfig)
        }
        
        self.view.setNeedsLayout()
    }
    
    func updateFediverseInteractions()
    {
        guard let federatedItem = self.app.federatedItem else { return }
                
        Task<Void, Never>(priority: .userInitiated) { @MainActor in
            do
            {
                let context: NSManagedObjectContext
                if let parentContext = self.app.managedObjectContext, self.app.objectID.isTemporaryID
                {
                    // Use child context since this a temporary context.
                    context = DatabaseManager.shared.persistentContainer.newBackgroundContext(withParent: parentContext)
                }
                else
                {
                    context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                }
                
                try await FederationManager.shared.updateInteractions(for: [federatedItem], in: context)
                                
                if let federatedItem = self.app.federatedItem
                {
                    self._isLiked = federatedItem.isLiked
                    self._likesCount = Int(federatedItem.likesCount)
                }
                else
                {
                    self._isLiked = false
                    self._likesCount = 0
                }
                
                self.update()
            }
            catch
            {
                Logger.main.error("Failed to fetch Fediverse interactions for app. \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func showNavigationBar()
    {
        self.navigationBarAppIconImageView.alpha = 1.0
        self.navigationBarAppNameLabel.alpha = 1.0
        self.navigationBarDownloadButton.alpha = 1.0
        
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
        self.navigationBarAppIconImageView.alpha = 0.0
        self.navigationBarAppNameLabel.alpha = 0.0
        self.navigationBarDownloadButton.alpha = 0.0
        
        self.updateNavigationBarAppearance(isHidden: true)
        
        self._preferredStatusBarStyle = .lightContent
        
        if #unavailable(iOS 17)
        {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    // Copied from HeaderContentViewController
    func updateNavigationBarAppearance(isHidden: Bool)
    {
        let barAppearance = self.navigationItem.standardAppearance as? NavigationBarAppearance ?? NavigationBarAppearance()
        barAppearance.ignoresUserInteraction = isHidden
        
        if #available(iOS 26, *)
        {
            self.navigationItem.rightBarButtonItem?.isHidden = isHidden
        }
        else
        {
            if isHidden
            {
                barAppearance.configureWithTransparentBackground()
            }
            else
            {
                barAppearance.configureWithDefaultBackground()
            }
            
            barAppearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
            
            let tintColor = isHidden ? UIColor.clear : self.app.tintColor ?? .altPrimary
            barAppearance.configureWithTintColor(tintColor)
        }
        
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
    
    func prepareSocialButtons()
    {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 17.0, weight: .semibold)
        
        // Containers
        if #available(iOS 26, *)
        {
            self.likesButtonContainerView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            self.moreButtonContainerView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))

            self.likesButtonContainerView.cornerConfiguration = .capsule()
            self.moreButtonContainerView.cornerConfiguration = .capsule()
        }
        else
        {
            self.likesButtonContainerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            self.moreButtonContainerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            
            self.likesButtonContainerView.tintColor = self.app.tintColor
            self.moreButtonContainerView.tintColor = self.app.tintColor
        }
        
        self.likesButtonContainerView.clipsToBounds = true
        self.moreButtonContainerView.clipsToBounds = true
        
        // Likes button
        self.likesButton = UIButton(type: .system)
        
        var likesConfig = UIButton.Configuration.plain()
        likesConfig.image = UIImage(systemName: "heart", withConfiguration: imageConfig)
        likesConfig.imagePadding = 2
        
        if self._likesCount > 0
        {
            likesConfig.title = String(self._likesCount)
        }
        
        likesConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        
        self.likesButton.configuration = likesConfig
        self.likesButton.addTarget(self, action: #selector(AppViewController.likeApp), for: .touchUpInside)
        self.likesButton.sizeToFit()
        
        // More button
        self.moreButton = UIButton(type: .system)
        
        var moreConfig = UIButton.Configuration.plain()
        moreConfig.image = UIImage(systemName: "ellipsis", withConfiguration: imageConfig)
        moreConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10)
        
        self.moreButton.configuration = moreConfig
        self.moreButton.showsMenuAsPrimaryAction = true
        
        let openURLAction = UIAction(title: NSLocalizedString("Open in Browser", comment: ""), image: UIImage(systemName: "safari"), handler: { [weak self] _ in
            guard let federatedItem = self?.app.federatedItem else { return }
            
            let federatedURL = federatedItem.resolvedBlueskyURL ?? federatedItem.url
            UIApplication.shared.open(federatedURL)
        })
        let showLikesAction = UIAction(title: NSLocalizedString("View Likes", comment: ""), image: UIImage(systemName: "heart"), handler: { [weak self] _ in
            self?.showLikes()
        })
        let shareAction = UIAction(title: NSLocalizedString("Share", comment: ""), image: UIImage(systemName: "square.and.arrow.up"), handler: { [weak self] _ in
            self?.shareApp()
        })

        self.moreButton.menu = UIMenu(children: [shareAction, showLikesAction, openURLAction])
        self.moreButton.sizeToFit()
        
        // Add buttons to their containers
        self.likesButtonContainerView.contentView.addSubview(self.likesButton)
        self.moreButtonContainerView.contentView.addSubview(self.moreButton)
        
        self.view.addSubview(self.likesButtonContainerView)
        self.view.addSubview(self.moreButtonContainerView)
        
        if self.app.federatedItem == nil || UserDefaults.shared.fediverseInteractionsDisabled
        {
            self.likesButtonContainerView.isHidden = true
            self.moreButtonContainerView.isHidden = true
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

extension AppViewController
{
    @IBAction func popViewController(_ sender: UIButton)
    {
        self.navigationController?.popViewController(animated: true)
    }
    
    @IBAction func performAppAction(_ sender: PillButton)
    {
        if let installedApp = self.app.installedApp
        {
            if let latestVersion = self.app.latestAvailableVersion, !installedApp.matches(latestVersion), !self.app.isPledgeRequired || self.app.isPledged
            {
                self.updateApp(installedApp, to: latestVersion)
            }
            else
            {
                self.open(installedApp)
            }
        }
        else
        {
            self.downloadApp()
        }
    }
    
    func downloadApp()
    {
        guard self.app.installedApp == nil else { return }
        
        Task<Void, Never>(priority: .userInitiated) { @MainActor in
            let (task, progress) = await AppManager.shared.installAsync(self.app, presentingViewController: self)
            if !task.isCancelled
            {
                self.bannerView.button.progress = progress
                self.navigationBarDownloadButton.progress = progress
            }
            
            do
            {
                _ = try await task.value
            }
            catch OperationError.cancelled
            {
                // Ignore
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.opensErrorLog = true
                    toastView.show(in: self)
                }
            }
            
            DispatchQueue.main.async {
                self.bannerView.button.progress = nil
                self.navigationBarDownloadButton.progress = nil
                self.update()
            }
        }
    }
    
    func updateApp(_ installedApp: InstalledApp, to version: AppVersion)
    {
        let previousProgress = AppManager.shared.installationProgress(for: installedApp)
        guard previousProgress == nil else {
            //TODO: Handle cancellation
            //previousProgress?.cancel()
            return
        }
        
        Task<Void, Never> { @MainActor in
            let (task, _) = await AppManager.shared.updateAsync(installedApp, to: version, presentingViewController: self)
            
            self.update()
            
            do
            {
                _ = try await task.value
                print("Updated app from AppViewController:", installedApp.bundleIdentifier)
            }
            catch OperationError.cancelled {}
            catch
            {
                let toastView = ToastView(error: error)
                toastView.opensErrorLog = true
                toastView.show(in: self)
            }
            
            self.update()
        }
    }
    
    @objc func showLikes()
    {
        guard let federatedItem = self.app.federatedItem else { return }
        
        let hostingController = UIHostingController(rootView: NavigationStack { FediverseLikesView(federatedItem: federatedItem) })
        if #available(iOS 26, *)
        {
            hostingController.view.backgroundColor = .clear
        }
        
        if let sheetController = hostingController.sheetPresentationController
        {
            sheetController.detents = [.medium(), .large()]
            sheetController.prefersGrabberVisible = true
        }
        
        self.present(hostingController, animated: true)
    }
    
    @objc func shareApp()
    {
        guard let shareURL = self.app.shareURL else { return }
                
        let activityViewController = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.moreButton
        activityViewController.popoverPresentationController?.sourceRect = self.moreButton.bounds
        self.present(activityViewController, animated: true)
    }
    
    @objc func likeApp()
    {
        guard let federatedItem = self.app.federatedItem else { return }
        
        Task<Void, Never> {
            let previousState = self._isLiked
            
            self._isLiked.toggle()
            self.update()
            
            do
            {
                if self._isLiked
                {
                    try await FederationManager.shared.like(federatedItem, presentingViewController: self)
                }
                else
                {
                    try await FederationManager.shared.unlike(federatedItem, presentingViewController: self)
                }
                
                self.hapticGenerator.notificationOccurred(.success)
            }
            catch
            {
                Logger.main.error("Failed to like app \(self.app.bundleIdentifier). \(error.localizedDescription, privacy: .public)")
                self.hapticGenerator.notificationOccurred(.error)
                
                await self.presentAlert(title: String(localized: "Unable to Like App"), message: error.localizedDescription)
                
                self._isLiked = previousState
            }
            
            self._likesCount = Int(federatedItem.likesCount)
            
            self.update()
        }
    }
}

private extension AppViewController
{
    @objc func didChangeApp(_ notification: Notification)
    {
        // Async so that AppManager.installationProgress(for:) is nil when we update.
        DispatchQueue.main.async {
            self.update()
        }
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

extension AppViewController: UIScrollViewDelegate
{
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    {
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
}
