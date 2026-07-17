//
//  NewsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices
import Combine

import AltStoreCore
import Roxas

import Nuke
import NukeExtensions

private class AppBannerFooterView: UICollectionReusableView
{
    let bannerView = AppBannerView(frame: .zero)
    let tapGestureRecognizer = UITapGestureRecognizer(target: nil, action: nil)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.addGestureRecognizer(self.tapGestureRecognizer)
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.bannerView)

        // The footer spans the full width (flow-layout footers ignore the section's
        // centering insets), so cap + center the banner to match the news cards.
        // 680 = the news card's content width (720) minus the card's ~20pt layout
        // margins on each side, so the banner lines up with the card's visible width.
        let preferredWidthConstraint = self.bannerView.widthAnchor.constraint(equalToConstant: 680)
        preferredWidthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.bannerView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.bannerView.leadingAnchor.constraint(greaterThanOrEqualTo: self.layoutMarginsGuide.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.trailingAnchor),
            preferredWidthConstraint,
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class NewsViewController: UICollectionViewController, PeekPopPreviewing
{
    // Nil == Show news from all sources.
    var source: Source?
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)
    private var retryButton: UIButton!
    
    private var prototypeCell: NewsCollectionViewCell!

    /// On wide (iPad) layouts, constrain news cards to a readable column rather
    /// than stretching them across the whole screen. iPhone widths are below this,
    /// so the layout there is unchanged.
    private let maximumContentWidth: CGFloat = 720

    private var lastLayoutWidth: CGFloat = 0

    // Cache
    private var cachedCellSizes = [String: CGSize]()
    private var cancellables = Set<AnyCancellable>()
    private var updateFediverseInteractionsResult: Result<Void, Error>?
    
    init?(source: Source?, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(NewsViewController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NewsViewController.didFetchSource(_:)), name: AppManager.didFetchSourceNotification, object: nil)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.backgroundColor = .altBackground
        
        self.prototypeCell = NewsCollectionViewCell.instantiate(with: NewsCollectionViewCell.nib!)
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Need to add dummy constraint + layout subviews before we can remove Interface Builder's width constraint.
        self.prototypeCell.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        self.prototypeCell.layoutIfNeeded()
        
        let constraints = self.prototypeCell.constraintsAffectingLayout(for: .horizontal)
        for constraint in constraints where constraint.identifier?.contains("Encapsulated-Layout-Width") == true
        {
            self.prototypeCell.removeConstraint(constraint)
        }
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(AppBannerFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner")
        
        (self as PeekPopPreviewing).registerForPreviewing(with: self, sourceView: self.collectionView)
        
        let refreshControl = UIRefreshControl(frame: .zero)
        refreshControl.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
        
        self.retryButton = UIButton(type: .system)
        self.retryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.retryButton.setTitle(NSLocalizedString("Try Again", comment: ""), for: .normal)
        self.retryButton.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.placeholderView.stackView.addArrangedSubview(self.retryButton)
        
        if let source = self.source
        {
            let tintColor = source.effectiveTintColor ?? .altPrimary
            self.view.tintColor = tintColor
            
            let appearance = NavigationBarAppearance()
            appearance.configureWithTintColor(tintColor)
            appearance.configureWithDefaultBackground()
            
            let edgeAppearance = appearance.copy()
            edgeAppearance.configureWithTransparentBackground()
            
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = edgeAppearance
        }
        
        self.preparePipeline()
        self.update()
    }
    
    override func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()

        if self.collectionView.contentInset.bottom != 20
        {
            // Triggers collection view update in iOS 13, which crashes if we do it in viewDidLoad()
            // since the database might not be loaded yet.
            self.collectionView.contentInset.bottom = 20
        }

        // Recompute the centered column when the available width changes (rotation,
        // sidebar collapse/expand) so it doesn't keep the previous orientation's inset.
        if self.collectionView.bounds.width != self.lastLayoutWidth
        {
            self.lastLayoutWidth = self.collectionView.bounds.width
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }
    
    override func viewIsAppearing(_ animated: Bool)
    {
        super.viewIsAppearing(animated)
        
        self.updateFediverseInteractionsIfNeeded()
    }
    
    deinit
    {
        NotificationCenter.default.removeObserver(self, name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AppManager.didFetchSourceNotification, object: nil)
    }
}

private extension NewsViewController
{
    func preparePipeline()
    {
        AppManager.shared.$updateSourcesResult
            .receive(on: RunLoop.main) // Delay to next run loop so we receive _current_ value (not previous value).
            .sink { [weak self] result in
                self?.update()
            }
            .store(in: &self.cancellables)
    }
    
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>
    {
        let fetchRequest = NewsItem.sortedFetchRequest(for: self.source)
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        
        // Use fetchedResultsController to split NewsItems up into sections.
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: #keyPath(NewsItem.objectID), cacheName: nil)
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, newsItem, indexPath) in
            guard let self else { return }
            
            let cell = cell as! NewsCollectionViewCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.configure(with: newsItem)
            
            cell.imageView.image = nil
            
            if newsItem.imageURL != nil
            {
                cell.imageView.isIndicatingActivity = true
                cell.imageView.isHidden = false
            }
            else
            {
                cell.imageView.isIndicatingActivity = false
                cell.imageView.isHidden = true
            }
            
            if let federatedItem = newsItem.federatedItem
            {
                cell.fediverseInteractionsView.isHidden = false
                cell.fediverseInteractionsView.tintColor = newsItem.effectiveTintColor
                cell.fediverseInteractionsView.shareHandler = { [weak self] _ in self }
                cell.fediverseInteractionsView.presentingViewController = self
                cell.fediverseInteractionsView.configure(with: federatedItem, isOpaque: true)
            }
            else
            {
                cell.fediverseInteractionsView.isHidden = true
            }
            
            let stackView = cell.titleLabel.superview!
            stackView.isAccessibilityElement = true
            stackView.accessibilityLabel = (cell.titleLabel.text ?? "") + ". " + (cell.captionLabel.text ?? "")
            
            if newsItem.storeApp != nil || newsItem.externalURL != nil
            {
                stackView.accessibilityTraits.insert(.button)
            }
            else
            {
                stackView.accessibilityTraits.remove(.button)
            }
        }
        dataSource.prefetchHandler = { (newsItem, indexPath, completionHandler) in
            guard let imageURL = newsItem.imageURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! NewsCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        dataSource.placeholderView = self.placeholderView
        
        return dataSource
    }
    
    @objc func updateSources()
    {
        Task<Void, Never> {
            await FederationManager.shared.resetCache()
            
            AppManager.shared.updateAllSources() { result in
                self.updateFediverseInteractionsResult = nil
                self.updateFediverseInteractionsIfNeeded()
                
                self.collectionView.refreshControl?.endRefreshing()
                
                guard case .failure(let error) = result else { return }
                
                if self.dataSource.itemCount > 0
                {
                    let toastView = ToastView(error: error)
                    toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                    toastView.show(in: self)
                }
            }
        }
    }
    
    func update()
    {
        switch AppManager.shared.updateSourcesResult
        {
        case nil:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.startAnimating()
            
        case .failure(let error):
            self.placeholderView.textLabel.isHidden = false
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch News", comment: "")
            self.placeholderView.detailTextLabel.text = error.localizedDescription
            
            self.retryButton.isHidden = false
            self.placeholderView.activityIndicatorView.stopAnimating()
            
        case .success:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = true
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.stopAnimating()
        }
    }
    
    func updateFediverseInteractionsIfNeeded()
    {
        guard self.updateFediverseInteractionsResult == nil else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        Task<Void, Never>(priority: .utility) { @MainActor in
            do
            {
                let newsItems = self.dataSource.fetchedResultsController.fetchedObjects ?? []
                let federatedItems = newsItems.compactMap(\.federatedItem)
                
                if let newsItem = newsItems.first
                {
                    let context: NSManagedObjectContext
                    if let parentContext = newsItem.managedObjectContext, newsItem.objectID.isTemporaryID
                    {
                        // Use child context since this a temporary context.
                        context = DatabaseManager.shared.persistentContainer.newBackgroundContext(withParent: parentContext)
                    }
                    else
                    {
                        context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                    }
                    
                    try await FederationManager.shared.updateInteractions(for: federatedItems, in: context)
                }
                
                Logger.main.info("Fetched \(federatedItems.count) NewsItem statuses in \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
                
                self.updateFediverseInteractionsResult = .success(())
            }
            catch
            {
                Logger.main.error("Failed to fetch Fediverse interactions for News tab. \(error.localizedDescription, privacy: .public)")
                self.updateFediverseInteractionsResult = .failure(error)
            }
        }
    }
}

private extension NewsViewController
{
    @objc func didFetchSource(_ notification: Notification)
    {
        // Reset cache in case source has started federating.
        self.cachedCellSizes.removeAll()
    }
    
    @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer)
    {
        guard let footerView = gestureRecognizer.view as? UICollectionReusableView else { return }
        
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView == footerView
        }) else { return }
        
        let item = self.dataSource.item(at: indexPath)
        guard let storeApp = item.storeApp else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
    
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView?.frame.contains(point) ?? false
        }) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        guard let storeApp = app.storeApp else { return }
        
        if let installedApp = storeApp.installedApp, !installedApp.isUpdateAvailable
        {
            self.open(installedApp)
        }
        else
        {
            self.install(storeApp, at: indexPath)
        }
    }
    
    @objc func install(_ storeApp: StoreApp, at indexPath: IndexPath)
    {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        Task<Void, Never>(priority: .userInitiated) { @MainActor in
            
            let task: Task<AsyncManaged<InstalledApp>, Error>
            if let installedApp = storeApp.installedApp, installedApp.isUpdateAvailable
            {
                let (updateTask, _) = await AppManager.shared.updateAsync(installedApp, presentingViewController: self)
                task = updateTask
            }
            else
            {
                let (installTask, _) = await AppManager.shared.installAsync(storeApp, presentingViewController: self)
                task = installTask
            }
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
            }
            
            do
            {
                _ = try await task.value
                print("Installed app:", storeApp.bundleIdentifier)
            }
            catch OperationError.cancelled {} // Ignore
            catch
            {
                let toastView = ToastView(error: error)
                toastView.opensErrorLog = true
                toastView.show(in: self)
            }
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
            }
        }
    }
}

private extension NewsViewController
{
    @objc func importApp(_ notification: Notification)
    {
        self.presentedViewController?.dismiss(animated: true, completion: nil)
    }
}

extension NewsViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let newsItem = self.dataSource.item(at: indexPath)
        
        if let externalURL = newsItem.externalURL
        {
            let safariViewController = SFSafariViewController(url: externalURL)
            safariViewController.preferredControlTintColor = newsItem.effectiveTintColor
            self.present(safariViewController, animated: true, completion: nil)
        }
        else if let storeApp = newsItem.storeApp
        {
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let item = self.dataSource.item(at: indexPath)
        
        let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner", for: indexPath) as! AppBannerFooterView
        guard let storeApp = item.storeApp else { return footerView }
        
        footerView.layoutMargins.left = self.view.layoutMargins.left
        footerView.layoutMargins.right = self.view.layoutMargins.right
        
        footerView.bannerView.button.isIndicatingActivity = false
        footerView.bannerView.configure(for: storeApp)
        
        footerView.bannerView.tintColor = storeApp.tintColor
        footerView.bannerView.button.addTarget(self, action: #selector(NewsViewController.performAppAction(_:)), for: .primaryActionTriggered)
        footerView.tapGestureRecognizer.addTarget(self, action: #selector(NewsViewController.handleTapGesture(_:)))
        
        NukeExtensions.loadImage(with: storeApp.iconURL, into: footerView.bannerView.iconImageView) { result in
            footerView.bannerView.iconImageView.isIndicatingActivity = false
            
            switch result
            {
            case .success: footerView.bannerView.iconImageView.backgroundColor = .clear
            case .failure: break
            }
        }
        
        return footerView
    }
}

extension NewsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {        
        let item = self.dataSource.item(at: indexPath)
        let globallyUniqueID = item.globallyUniqueID ?? item.identifier
        let width = self.contentWidth(in: collectionView)

        // Key the cache by width as well as item: the available width now changes
        // on iPad (rotation, sidebar collapse/expand), and a size cached at one
        // width must not be reused at another or the cell gets squeezed.
        let cacheKey = "\(globallyUniqueID)|\(Int(width))"

        if let previousSize = self.cachedCellSizes[cacheKey]
        {
            return previousSize
        }

        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }

        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)

        let size = self.prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.cachedCellSizes[cacheKey] = size
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        let item = self.dataSource.item(at: IndexPath(row: 0, section: section))
        
        if item.storeApp != nil
        {
            return CGSize(width: 88, height: 88)
        }
        else
        {
            return .zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        // Center the constrained column when the collection view is wider than it.
        let horizontalInset = max(0, (collectionView.bounds.width - self.contentWidth(in: collectionView)) / 2)
        var insets = UIEdgeInsets(top: 30, left: horizontalInset, bottom: 13, right: horizontalInset)

        if section == 0
        {
            insets.top = 10
        }

        return insets
    }

    /// The width news cards are laid out at: the full width on iPhone, but capped
    /// and centered on wider (iPad) layouts so cards don't stretch edge-to-edge.
    private func contentWidth(in collectionView: UICollectionView) -> CGFloat
    {
        return min(collectionView.bounds.width, self.maximumContentWidth)
    }
}

extension NewsViewController: UIViewControllerPreviewingDelegate
{
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        if let indexPath = self.collectionView.indexPathForItem(at: location), let cell = self.collectionView.cellForItem(at: indexPath)
        {
            // Previewing news item.
            
            previewingContext.sourceRect = cell.frame
            
            let newsItem = self.dataSource.item(at: indexPath)
            
            if let externalURL = newsItem.externalURL
            {
                let safariViewController = SFSafariViewController(url: externalURL)
                safariViewController.preferredControlTintColor = newsItem.effectiveTintColor
                return safariViewController
            }
            else if let storeApp = newsItem.storeApp
            {
                let appViewController = AppViewController.makeAppViewController(app: storeApp)
                return appViewController
            }
            
            return nil
        }
        else
        {
            // Previewing app banner (or nothing).
            
            let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
            
            guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
                let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath)
                return layoutAttributes?.frame.contains(location) ?? false
            }) else { return nil }
            
            guard let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
            previewingContext.sourceRect = layoutAttributes.frame
            
            let item = self.dataSource.item(at: indexPath)
            guard let storeApp = item.storeApp else { return nil }
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
        }
    }
    
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        if let safariViewController = viewControllerToCommit as? SFSafariViewController
        {
            self.present(safariViewController, animated: true, completion: nil)
        }
        else
        {
            self.navigationController?.pushViewController(viewControllerToCommit, animated: true)
        }
    }
}
