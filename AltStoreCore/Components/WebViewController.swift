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
    
    public private(set) lazy var backButton: UIBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: self, action: #selector(WebViewController.goBack(_:)))
    public private(set) lazy var forwardButton: UIBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.forward"), style: .plain, target: self, action: #selector(WebViewController.goForward(_:)))
    public private(set) lazy var shareButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(WebViewController.shareLink(_:)))
    
    public private(set) lazy var reloadButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(WebViewController.refresh(_:)))
    public private(set) lazy var stopLoadingButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(WebViewController.refresh(_:)))
    
    public private(set) lazy var doneButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(WebViewController.dismissWebViewController(_:)))
    
    //MARK: Private Properties
    private let progressView = UIProgressView()
    private lazy var refreshButton: UIBarButtonItem = self.reloadButton
    
    private let initialReqest: URLRequest?
    private var ignoreUpdateProgress: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    public required init(request: URLRequest?, configuration: WKWebViewConfiguration = WKWebViewConfiguration())
    {
        self.initialReqest = request
                
        super.init(nibName: nil, bundle: nil)
        
        self.webView = WKWebView(frame: CGRectZero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
        
        self.progressView.progressViewStyle = .bar
        self.progressView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.progressView.progress = 0.5
        self.progressView.alpha = 0.0
        self.progressView.isHidden = true
    }
    
    public convenience init(url: URL?, configuration: WKWebViewConfiguration = WKWebViewConfiguration())
    {
        if let url
        {
            let request = URLRequest(url: url)
            self.init(request: request, configuration: configuration)
        }
        else
        {
            self.init(request: nil, configuration: configuration)
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
        self.navigationController?.view.tintColor = .altPrimary
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        }
        
        if let toolbar = self.navigationController?.toolbar, #available(iOS 15, *)
        {
            toolbar.scrollEdgeAppearance = toolbar.standardAppearance
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
        
        self.navigationController?.setToolbarHidden(false, animated: false)
        
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
    
    deinit
    {
        self.webView.stopLoading()
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
        
        self.navigationItem.leftBarButtonItem = self.doneButton
        self.navigationItem.rightBarButtonItem = self.refreshButton
        
        self.toolbarItems = [self.backButton, .fixedSpace(70), self.forwardButton, .flexibleSpace(), self.shareButton]
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
        let url = self.webView.url ?? (NSURL() as URL)
        
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityViewController.modalPresentationStyle = .popover
        activityViewController.popoverPresentationController?.barButtonItem = sender
        self.present(activityViewController, animated: true)
    }
    
    func dismissWebViewController(_ sender: UIBarButtonItem)
    {
        self.delegate?.webViewControllerDidFinish(self)
        
        self.parent?.dismiss(animated: true)
    }
}
