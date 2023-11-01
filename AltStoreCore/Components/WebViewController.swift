//
//  WebViewController.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/31/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import WebKit
import Combine

public protocol WebViewControllerDelegate: NSObject
{
    func webViewControllerDidFinish(_ webViewController: WebViewController)
}

public class WebViewController: UIViewController
{
    //MARK: Public Properties
    public weak var delegate: WebViewControllerDelegate?
    
    // WKWebView used to display webpages
    public private(set) var webView: WKWebView!
    
    public private(set) lazy var backButton: UIBarButtonItem = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(WebViewController.goBack(_:)))
    public private(set) lazy var forwardButton: UIBarButtonItem = UIBarButtonItem(image: nil, style: .plain, target: self, action: #selector(WebViewController.goForward(_:)))
    public private(set) lazy var shareButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(WebViewController.shareLink(_:)))
    
    public private(set) lazy var reloadButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(WebViewController.refresh(_:)))
    public private(set) lazy var stopLoadingButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(WebViewController.refresh(_:)))
    
    public private(set) lazy var doneButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(WebViewController.dismissWebViewController(_:)))
    
    //MARK: Private Properties
    private let progressView = UIProgressView()
    
    private lazy var refreshButton: UIBarButtonItem = self.reloadButton
    
    private let initialReqest: URLRequest?
    private var ignoreUpdateProgress: Bool = false
    
    private var cancellables: Set<AnyCancellable> = []

    public required init(request: URLRequest?)
    {
        self.initialReqest = request
                
        super.init(nibName: nil, bundle: nil)
        
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(self, forURLScheme: "altstore")
        configuration.websiteDataStore = .default()
        
        self.webView = WKWebView(frame: CGRectZero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
        
        self.progressView.progressViewStyle = .bar
        self.progressView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.progressView.progress = 0.5
        self.progressView.alpha = 0.0
        self.progressView.isHidden = true
        
        self.backButton.image = UIImage(systemName: "chevron.backward")
        self.forwardButton.image = UIImage(systemName: "chevron.forward")
    }
    
    public convenience init(url: URL?)
    {
        if let url
        {
            let request = URLRequest(url: url)
            self.init(request: request)
        }
        else
        {
            self.init(request: nil)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //MARK: UIViewController
    
    public override func loadView()
    {
        self.preparePipeline()
        
        if let request = self.initialReqest
        {
            self.webView.load(request)
        }
        
        self.view = self.webView
    }
    
    public override func viewDidLoad() 
    {
        super.viewDidLoad()
        
        self.navigationController?.isModalInPresentation = true
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        }
    }
    
    public override func viewIsAppearing(_ animated: Bool)
    {
        super.viewIsAppearing(animated)
        
        if self.webView.estimatedProgress < 1.0
        {
            self.transitionCoordinator?.animate(alongsideTransition: { context in
                self.showProgressBar(animated: true)
            }) { context in
                if context.isCancelled
                {
                    self.hideProgressBar(animated: false)
                }
            }
        }
        
        if self.traitCollection.horizontalSizeClass == .regular
        {
            self.navigationController?.setToolbarHidden(true, animated: false)
        }
        else
        {
            self.navigationController?.setToolbarHidden(false, animated: false)
        }
        
        self.update()
    }
    
    public override func viewWillDisappear(_ animated: Bool)
    {
        super.viewWillDisappear(animated)
        
        var shouldHideToolbarItems = true
        
        if let toolbarItems = self.navigationController?.topViewController?.toolbarItems
        {
            if toolbarItems.count > 0
            {
                shouldHideToolbarItems = false
            }
        }
        
        if shouldHideToolbarItems
        {
            self.navigationController?.setToolbarHidden(true, animated: false)
        }
        
        self.transitionCoordinator?.animate(alongsideTransition: { context in
            self.hideProgressBar(animated: true)
        }) { (context) in
            if context.isCancelled && self.webView.estimatedProgress < 1.0
            {
                self.showProgressBar(animated: false)
            }
        }
    }
    
    public override func didMove(toParent parent: UIViewController?)
    {
        super.didMove(toParent: parent)
        
        if parent == nil
        {
            self.webView.stopLoading()
        }
    }
}

private extension WebViewController
{
    func preparePipeline()
    {
        self.webView.publisher(for: \.title, options: [.initial, .new])
            .sink { [weak self] title in
                self?.title = title
            }
            .store(in: &self.cancellables)
        
        self.webView.publisher(for: \.estimatedProgress, options: [.new])
            .sink { [weak self] progress in
                self?.updateProgress(progress)
            }
            .store(in: &self.cancellables)
        
        Publishers.Merge3(
            self.webView.publisher(for: \.isLoading, options: [.new]),
            self.webView.publisher(for: \.canGoBack, options: [.new]),
            self.webView.publisher(for: \.canGoForward, options: [.new])
        )
        .sink { [weak self] _ in
            self?.update()
        }
        .store(in: &self.cancellables)
    }
    
    func update()
    {
        if self.webView.isLoading
        {
            self.refreshButton = self.stopLoadingButton
        }
        else
        {
            self.refreshButton = self.reloadButton
        }
        
        self.backButton.isEnabled = self.webView.canGoBack
        self.forwardButton.isEnabled = self.webView.canGoForward
        
        if self.traitCollection.horizontalSizeClass == .regular
        {
            self.toolbarItems = nil
            
            let fixedSpaceItem = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            fixedSpaceItem.width = 20.0
            
            let reloadButtonFixedSpaceItem = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
            reloadButtonFixedSpaceItem.width = fixedSpaceItem.width
            
            if self.refreshButton == self.stopLoadingButton
            {
                reloadButtonFixedSpaceItem.width = fixedSpaceItem.width + 1
            }
            
            let items = [self.doneButton, fixedSpaceItem, self.shareButton, fixedSpaceItem, self.refreshButton, reloadButtonFixedSpaceItem, self.forwardButton, fixedSpaceItem, self.backButton, fixedSpaceItem]
            self.navigationItem.rightBarButtonItems = items
        }
        else
        {
            // We have to set rightBarButtonItems instead of simply rightBarButtonItem to properly clear previous buttons
            self.navigationItem.rightBarButtonItems = [self.doneButton]
            
            let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            self.toolbarItems = [self.backButton, flexibleSpaceItem, self.forwardButton, flexibleSpaceItem, self.refreshButton, flexibleSpaceItem, self.shareButton]
        }
    }
    
    func updateProgress(_ progress: Double)
    {
        if self.progressView.isHidden
        {
            self.showProgressBar(animated: true)
        }
        
        if self.ignoreUpdateProgress
        {
            self.ignoreUpdateProgress = false
            self.hideProgressBar(animated: true)
        }
        else if progress < Double(self.progressView.progress)
        {
            // If progress is less than self.progressView.progress, another webpage began to load before the first one completed
            // In this case, we set the progress back to 0.0, and then wait until the next updateProgress, because it results in a much better animation
            
            self.progressView.setProgress(0.0, animated: false)
        }
        else
        {
            UIView.animate(withDuration: 0.4, animations: {
                self.progressView.setProgress(Float(progress), animated: true)
            }, completion: { (finished) in
                if progress == 1.0
                {
                    // This delay serves two purposes. One, it keeps the progress bar on screen just a bit longer so it doesn't appear to disappear too quickly.
                    // Two, it allows us to prevent the progress bar from disappearing if the user actually started loading another webpage before the current one finished loading.
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if self.webView.estimatedProgress == 1.0
                        {
                            self.hideProgressBar(animated: true)
                        }
                    }
                }
            })
        }
    }
    
    func showProgressBar(animated: Bool)
    {
        let navigationBarBounds = self.navigationController?.navigationBar.bounds ?? .zero
        self.progressView.frame = CGRect(x: 0, y: navigationBarBounds.height - self.progressView.bounds.height, width: navigationBarBounds.width, height: self.progressView.bounds.height)
        
        self.navigationController?.navigationBar.addSubview(self.progressView)
        
        self.progressView.setProgress(Float(self.webView.estimatedProgress), animated: false)
        self.progressView.isHidden = false
        
        if animated
        {
            UIView.animate(withDuration: 0.4) {
                self.progressView.alpha = 1.0
            }
        }
        else
        {
            self.progressView.alpha = 1.0
        }
    }
    
    func hideProgressBar(animated: Bool)
    {
        if animated
        {
            UIView.animate(withDuration: 0.4, animations: {
                self.progressView.alpha = 0.0
            }, completion: { (finished) in
                self.progressView.setProgress(0.0, animated: false)
                self.progressView.isHidden = true
                self.progressView.removeFromSuperview()
            })
        }
        else
        {
            self.progressView.alpha = 0.0
            
            // Completion
            self.progressView.setProgress(0.0, animated: false)
            self.progressView.isHidden = true
            self.progressView.removeFromSuperview()
        }
    }
}

@objc
private extension WebViewController
{
    func goBack(_ sender: UIBarButtonItem)
    {
        self.webView.goBack()
    }
    
    func goForward(_ sender: UIBarButtonItem)
    {
        self.webView.goForward()
    }
    
    func refresh(_ sender: UIBarButtonItem)
    {
        if self.webView.isLoading
        {
            self.ignoreUpdateProgress = true
            self.webView.stopLoading()
        }
        else
        {
            if let initialRequest = self.initialReqest, self.webView.url == nil && self.webView.backForwardList.backList.count == 0
            {
                self.webView.load(initialRequest)
            }
            else
            {
                self.webView.reload()
            }
        }
    }
    
    func shareLink(_ sender: UIBarButtonItem)
    {
        
    }
    
    func dismissWebViewController(_ sender: UIBarButtonItem)
    {
        self.delegate?.webViewControllerDidFinish(self)
        
        self.parent?.dismiss(animated: true)
    }
}

extension WebViewController: WKURLSchemeHandler
{
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask)
    {
        guard let callbackURL = urlSchemeTask.request.url else { return }
        
        Logger.main.debug("WebViewController intercepted handling url scheme!")
        
        PatreonAPI.shared.handleOAuthCallbackURL(callbackURL)
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) 
    {
        Logger.main.debug("WebViewController stopped handling url scheme.")
    }
}