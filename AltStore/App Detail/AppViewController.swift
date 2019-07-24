//
//  AppViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class AppViewController: UIViewController
{
    var app: App!
    
    private var contentViewController: AppContentViewController!
    private var contentViewControllerShadowView: UIView!
    
    private var blurAnimator: UIViewPropertyAnimator?
    
    private var contentSizeObservation: NSKeyValueObservation?
    
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentView: UIView!
    
    @IBOutlet private var headerView: UIView!
    @IBOutlet private var headerContentView: UIView!
    
    @IBOutlet private var backButton: UIButton!
    @IBOutlet private var backButtonContainerView: UIVisualEffectView!
    
    @IBOutlet private var nameLabel: UILabel!
    @IBOutlet private var developerLabel: UILabel!
    @IBOutlet private var downloadButton: PillButton!
    @IBOutlet private var appIconImageView: UIImageView!
    
    @IBOutlet private var backgroundAppIconImageView: UIImageView!
    @IBOutlet private var backgroundBlurView: UIVisualEffectView!
    
    private var _isEnteringForeground = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
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
        self.contentViewController.tableView.showsVerticalScrollIndicator = false
        
        self.headerView.frame = CGRect(x: 0, y: 0, width: 300, height: 93)
        self.headerView.layer.cornerRadius = 24
        self.headerView.layer.masksToBounds = true
        
        // Bring to front so the scroll indicators are visible.
        self.view.bringSubviewToFront(self.scrollView)
        self.scrollView.isUserInteractionEnabled = false
        
        self.nameLabel.text = self.app.name
        self.developerLabel.text = self.app.developerName
        self.developerLabel.textColor = self.app.tintColor
        self.appIconImageView.image = UIImage(named: self.app.iconName)
        self.downloadButton.tintColor = self.app.tintColor
        self.backgroundAppIconImageView.image = UIImage(named: self.app.iconName)
        
        self.backButtonContainerView.tintColor = self.app.tintColor
        
        self.contentSizeObservation = self.contentViewController.tableView.observe(\.contentSize) { (tableView, change) in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        
        self.update()
        
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.didChangeApp(_:)), name: .NSManagedObjectContextObjectsDidChange, object: DatabaseManager.shared.viewContext)
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        
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
        
        self.hideNavigationBar()
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
            if context.isCancelled
            {
                self.hideNavigationBar(for: navigationController)
            }
            else
            {
                self.showNavigationBar(for: navigationController)
            }
        })
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "embedAppContentViewController" else { return }
        
        self.contentViewController = segue.destination as? AppContentViewController
        self.contentViewController.app = self.app
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if self._isEnteringForeground
        {
            // Returning from background messes up some of our UI, so reset affected components now.
            
            if self.navigationController?.topViewController == self
            {
                self.hideNavigationBar()
            }
            
            self.prepareBlur()
            
            self._isEnteringForeground = false
        }
        
        let statusBarHeight = UIApplication.shared.statusBarFrame.height
        
        let inset = 12 as CGFloat
        let padding = 20 as CGFloat
        
        let backButtonSize = self.backButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        let backButtonFrame = CGRect(x: inset, y: statusBarHeight,
                                     width: backButtonSize.width + 20, height: backButtonSize.height + 20)
        
        var headerFrame = CGRect(x: inset, y: 0, width: self.view.bounds.width - inset * 2, height: self.headerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.width)
        
        let minimumHeaderY = backButtonFrame.maxY + 8
        
        let minimumContentY = minimumHeaderY + headerFrame.height + padding
        let maximumContentY = self.view.bounds.width * 0.75
        
        // A full blur is too much, so we reduce the visible blur by 0.3, resulting in 70% blur.
        let minimumBlurFraction = 0.3 as CGFloat
        
        let difference = (maximumContentY - minimumContentY)
        
        if self.scrollView.contentOffset.y > difference
        {
            // Full screen
            
            headerFrame.origin.y = minimumHeaderY
            contentFrame.origin.y = minimumContentY
            backgroundIconFrame.origin.y = 0
            
            self.contentViewController.tableView.contentOffset.y = self.scrollView.contentOffset.y - difference
        }
        else
        {
            // Partial screen
            
            contentFrame.origin.y = maximumContentY - self.scrollView.contentOffset.y
            headerFrame.origin.y = contentFrame.origin.y - padding - headerFrame.height
            
            let cornerRadius = self.contentViewControllerShadowView.layer.cornerRadius
            
            // Stretch the app icon image to fill additional vertical space if necessary.
            let height = max(contentFrame.origin.y + cornerRadius * 2, backgroundIconFrame.height)
            backgroundIconFrame.size.height = height
            
            // Keep content table view's content offset at the top.
            self.contentViewController.tableView.contentOffset.y = 0
            
            if self.scrollView.contentOffset.y < 0
            {
                // Determine how much to lessen blur by.
                
                let range = 75 as CGFloat
                
                let fraction = min(-self.scrollView.contentOffset.y, range) / range
                
                let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
                self.blurAnimator?.fractionComplete = fractionComplete
            }
            else
            {
                // Set blur to default.
                
                self.blurAnimator?.fractionComplete = minimumBlurFraction
            }
        }
        
        // Keep background app icon centered in gap between top of content and top of screen.
        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2
        
        // Set frames.
        self.contentViewController.view.superview?.frame = contentFrame
        self.headerView.frame = headerFrame
        self.backgroundAppIconImageView.frame = backgroundIconFrame
        self.backgroundBlurView.frame = backgroundIconFrame
        self.backButtonContainerView.frame = backButtonFrame
        
        self.headerContentView.frame = CGRect(x: 0, y: 0, width: self.headerView.bounds.width, height: self.headerView.bounds.height)
        self.contentViewControllerShadowView.frame = self.contentViewController.view.frame
        
        self.backButtonContainerView.layer.cornerRadius = self.backButtonContainerView.bounds.midY
        
        self.scrollView.scrollIndicatorInsets.top = statusBarHeight
        
        // Adjust content offset + size.
        let contentOffset = self.scrollView.contentOffset
        
        var contentSize = self.contentViewController.tableView.contentSize
        contentSize.height += minimumContentY + self.view.safeAreaInsets.bottom + self.contentViewController.tableView.contentInset.bottom
        
        self.scrollView.contentSize = contentSize
        self.scrollView.contentOffset = contentOffset
    }
    
    deinit
    {
        self.blurAnimator?.stopAnimation(true)
    }
}

private extension AppViewController
{
    func update()
    {
        self.downloadButton.isIndicatingActivity = false
        
        if self.app.installedApp == nil
        {
            self.downloadButton.setTitle(NSLocalizedString("FREE", comment: ""), for: .normal)
            self.downloadButton.isInverted = false
        }
        else
        {
            self.downloadButton.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
            self.downloadButton.isInverted = true
        }
        
        let progress = AppManager.shared.installationProgress(for: self.app)
        self.downloadButton.progress = progress
    }
    
    func showNavigationBar(for navigationController: UINavigationController? = nil)
    {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.barStyle = .default
        navigationController?.navigationBar.alpha = 1.0
        navigationController?.navigationBar.setBackgroundImage(nil, for: .default)
    }
    
    func hideNavigationBar(for navigationController: UINavigationController? = nil)
    {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.alpha = 0.0
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
    }
    
    func prepareBlur()
    {
        if let animator = self.blurAnimator
        {
            animator.stopAnimation(true)
        }
        
        self.backgroundBlurView.effect = self._backgroundBlurEffect
        self.backgroundBlurView.contentView.backgroundColor = self._backgroundBlurTintColor
        
        self.blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) {
            self.backgroundBlurView.effect = nil
            self.backgroundBlurView.contentView.backgroundColor = .clear
        }

        self.blurAnimator?.startAnimation()
        self.blurAnimator?.pauseAnimation()
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
            self.open(installedApp)
        }
        else
        {
            self.downloadApp()
        }
    }
    
    func downloadApp()
    {
        guard self.app.installedApp == nil else { return }
        
        let progress = AppManager.shared.install(self.app, presentingViewController: self) { (result) in
            do
            {
                _ = try result.get()
            }
            catch OperationError.cancelled
            {
                // Ignore
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController!.view, duration: 2)
                }
            }
            
            DispatchQueue.main.async {
                self.downloadButton.progress = nil
                self.update()
            }
        }
        
        self.downloadButton.progress = progress
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

private extension AppViewController
{
    @objc func didChangeApp(_ notification: Notification)
    {
        self.update()
    }
    
    @objc func willEnterForeground(_ notification: Notification)
    {
        guard let navigationController = self.navigationController, navigationController.topViewController == self else { return }
        
        self._isEnteringForeground = true
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
