//
//  BrowseViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore
import Roxas

import Nuke

class BrowseViewController: UICollectionViewController, PeekPopPreviewing
{
    // Nil == Show apps from all sources.
    let source: Source?
    
    private(set) var category: StoreCategory? {
        didSet {
            self.updateDataSource()
            self.update()
        }
    }
    
    var searchPredicate: NSPredicate? {
        didSet {
            self.updateDataSource()
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)
    
    private let prototypeCell = AppCardCollectionViewCell(frame: .zero)
    private var sortButton: UIBarButtonItem?
    
    private var preferredAppSorting: AppSorting = UserDefaults.shared.preferredAppSorting
    
    private var cancellables = Set<AnyCancellable>()
    
    private var titleStackView: UIStackView!
    private var titleSourceIconView: AppIconImageView!
    private var titleCategoryIconView: UIImageView!
    private var titleLabel: UILabel!
    
    init?(source: Source?, coder: NSCoder)
    {
        self.source = source
        self.category = nil
        
        super.init(coder: coder)
    }
    
    init?(category: StoreCategory?, coder: NSCoder)
    {
        self.source = nil
        self.category = category
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder)
    {
        self.source = nil
        self.category = nil
        
        super.init(coder: coder)
    }
    
    private var cachedItemSizes = [String: CGSize]()
    
    @IBOutlet private var sourcesBarButtonItem: UIBarButtonItem!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.backgroundColor = .altBackground
        self.collectionView.alwaysBounceVertical = true
        
        self.dataSource.searchController.searchableKeyPaths = [#keyPath(StoreApp.name),
                                                               #keyPath(StoreApp.subtitle),
                                                               #keyPath(StoreApp.developerName),
                                                               #keyPath(StoreApp.bundleIdentifier)]
        self.navigationItem.searchController = self.dataSource.searchController
        
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(AppCardCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        let collectionViewLayout = self.collectionViewLayout as! UICollectionViewFlowLayout
        collectionViewLayout.minimumLineSpacing = 30
        
        (self as PeekPopPreviewing).registerForPreviewing(with: self, sourceView: self.collectionView)
        
        let refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in
            self?.updateSources()
        })
        self.collectionView.refreshControl = refreshControl
        
        if self.category != nil, #available(iOS 16, *)
        {
            let categoriesMenu = UIMenu(children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    let actions = self?.makeCategoryActions() ?? []
                    completion(actions)
                }
            ])
            
            self.navigationItem.titleMenuProvider = { _ in categoriesMenu }
        }
        
        self.titleSourceIconView = AppIconImageView(style: .circular)
        
        self.titleCategoryIconView = UIImageView(frame: .zero)
        self.titleCategoryIconView.contentMode = .scaleAspectFit
        
        self.titleLabel = UILabel()
        self.titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        
        self.titleStackView = UIStackView(arrangedSubviews: [self.titleSourceIconView, self.titleCategoryIconView, self.titleLabel])
        self.titleStackView.spacing = 4
        self.titleStackView.translatesAutoresizingMaskIntoConstraints = false
        
        self.navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 16, *)
        {
            self.navigationItem.preferredSearchBarPlacement = .automatic
        }
        
        if #available(iOS 15, *)
        {
            self.prepareAppSorting()
        }
        
        self.preparePipeline()
        
        NSLayoutConstraint.activate([
            // Source icon = equal width and height
            self.titleSourceIconView.heightAnchor.constraint(equalToConstant: 26),
            self.titleSourceIconView.widthAnchor.constraint(equalTo: self.titleSourceIconView.heightAnchor),
            
            // Category icon = constant height, variable widths
            self.titleCategoryIconView.heightAnchor.constraint(equalToConstant: 26)
        ])
        
        self.updateDataSource()
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.update()
    }
    
    override func viewDidDisappear(_ animated: Bool) 
    {
        super.viewDidDisappear(animated)
        
        self.navigationController?.navigationBar.tintColor = nil
    }
}

private extension BrowseViewController
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
    
    func makeFetchRequest() -> NSFetchRequest<StoreApp>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        
        let predicate = StoreApp.visibleAppsPredicate
        
        if let source = self.source
        {
            let filterPredicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp._source), source)
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [filterPredicate, predicate])
        }
        else if let category = self.category
        {
            let categoryPredicate = switch category {
            case .other: StoreApp.otherCategoryPredicate
            default: NSPredicate(format: "%K == %@", #keyPath(StoreApp._category), category.rawValue)
            }
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [categoryPredicate, predicate])
        }
        else
        {
            fetchRequest.predicate = predicate
        }
        
        var sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                               NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                               NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true)]
        
        switch self.preferredAppSorting
        {
        case .default:
            let descriptor = NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: self.preferredAppSorting.isAscending)
            sortDescriptors.insert(descriptor, at: 0)
            
        case .name:
            // Already sorting by name, no need to prepend additional sort descriptor.
            break
            
        case .developer:
            let descriptor = NSSortDescriptor(keyPath: \StoreApp.developerName, ascending: self.preferredAppSorting.isAscending)
            sortDescriptors.insert(descriptor, at: 0)
            
        case .lastUpdated:
            let descriptor = NSSortDescriptor(keyPath: \StoreApp.latestSupportedVersion?.date, ascending: self.preferredAppSorting.isAscending)
            sortDescriptors.insert(descriptor, at: 0)
        }
        
        fetchRequest.sortDescriptors = sortDescriptors
        
        return fetchRequest
    }
    
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = self.makeFetchRequest()
        
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: context)
        dataSource.placeholderView = self.placeholderView
        dataSource.cellConfigurationHandler = { [weak self] (cell, app, indexPath) in
            guard let self else { return }
            
            let cell = cell as! AppCardCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            let showSourceIcon = (self.source == nil) // Hide source icon if redundant
            cell.configure(for: app, showSourceIcon: showSourceIcon)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            
            cell.bannerView.button.addTarget(self, action: #selector(BrowseViewController.performAppAction(_:)), for: .primaryActionTriggered)
            cell.bannerView.button.activityIndicatorView.style = .medium
            cell.bannerView.button.activityIndicatorView.color = .white
            
            let tintColor = app.tintColor ?? .altPrimary
            cell.tintColor = tintColor
        }
        dataSource.prefetchHandler = { (storeApp, indexPath, completionHandler) -> Foundation.Operation? in
            let iconURL = storeApp.iconURL
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: iconURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { [weak dataSource] (cell, image, indexPath, error) in
            let cell = cell as! AppCardCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error, let dataSource
            {
                let app = dataSource.item(at: indexPath)
                Logger.main.debug("Failed to load app icon from \(app.iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return dataSource
    }
    
    func updateDataSource()
    {
        let fetchRequest = self.makeFetchRequest()
        
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        self.dataSource.fetchedResultsController = fetchedResultsController
        
        self.dataSource.predicate = self.searchPredicate
    }
    
    func updateSources()
    {
        AppManager.shared.updateAllSources { result in
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
    
    func update()
    {
        if self.searchPredicate != nil
        {
            self.placeholderView.textLabel.text = NSLocalizedString("No Apps", comment: "")
            self.placeholderView.textLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Please make sure your spelling is correct, or try searching for another app.", comment: "")
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.activityIndicatorView.stopAnimating()
        }
        else
        {
            switch AppManager.shared.updateSourcesResult
            {
            case nil:
                self.placeholderView.textLabel.isHidden = true
                self.placeholderView.detailTextLabel.isHidden = false
                
                self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
                
                self.placeholderView.activityIndicatorView.startAnimating()
                
            case .failure(let error):
                self.placeholderView.textLabel.isHidden = false
                self.placeholderView.detailTextLabel.isHidden = false
                
                self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch Apps", comment: "")
                self.placeholderView.detailTextLabel.text = error.localizedDescription
                
                self.placeholderView.activityIndicatorView.stopAnimating()
                
            case .success:
                self.placeholderView.textLabel.text = NSLocalizedString("No Apps", comment: "")
                self.placeholderView.textLabel.isHidden = false
                self.placeholderView.detailTextLabel.isHidden = true
                
                self.placeholderView.activityIndicatorView.stopAnimating()
            }
        }
        
        let tintColor: UIColor
        
        if let source = self.source
        {
            tintColor = source.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
            
            self.title = source.name
                        
            self.titleSourceIconView.backgroundColor = tintColor
            self.titleSourceIconView.isHidden = false
            
            self.titleCategoryIconView.isHidden = true
            
            if let iconURL = source.effectiveIconURL
            {
                Nuke.loadImage(with: iconURL, into: self.titleSourceIconView) { result in
                    switch result
                    {
                    case .failure(let error): Logger.main.error("Failed to fetch source icon at \(iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
                    case .success: self.titleSourceIconView.backgroundColor = .white
                    }
                }
            }
        }
        else if let category = self.category
        {
            tintColor = category.tintColor
            
            self.title = category.localizedName
            
            let image = UIImage(systemName: category.filledSymbolName)?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            self.titleCategoryIconView.image = image
            self.titleCategoryIconView.isHidden = false
            
            self.titleSourceIconView.isHidden = true
        }
        else
        {
            tintColor = .altPrimary
            
            self.title = NSLocalizedString("Browse", comment: "")
            
            self.titleSourceIconView.isHidden = true
            self.titleCategoryIconView.isHidden = true
        }
        
        self.titleLabel.text = self.title
        self.titleStackView.sizeToFit()
        self.navigationItem.titleView = self.titleStackView
        
        self.view.tintColor = tintColor
        
        let appearance = NavigationBarAppearance()
        appearance.configureWithTintColor(tintColor)
        appearance.configureWithDefaultBackground()
        
        let edgeAppearance = appearance.copy()
        edgeAppearance.configureWithTransparentBackground()
        
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = edgeAppearance
        
        // Necessary to tint UISearchController's inline bar button.
        self.navigationController?.navigationBar.tintColor = tintColor
        
        if let sortButton
        {
            sortButton.image = sortButton.image?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        }
    }
    
    func makeCategoryActions() -> [UIAction]
    {
        let handler = { [weak self] (category: StoreCategory) in
            self?.category = category
        }
        
        let fetchRequest = NSFetchRequest(entityName: StoreApp.entity().name!) as NSFetchRequest<NSDictionary>
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.returnsDistinctResults = true
        fetchRequest.propertiesToFetch = [#keyPath(StoreApp._category)]
        fetchRequest.predicate = StoreApp.visibleAppsPredicate
        
        do
        {
            let dictionaries = try DatabaseManager.shared.viewContext.fetch(fetchRequest)
            
            // Keep nil values
            let categories = dictionaries.map { $0[#keyPath(StoreApp._category)] as? String? ?? nil }.map { rawCategory -> StoreCategory in
                guard let rawCategory else { return .other }
                return StoreCategory(rawValue: rawCategory) ?? .other
            }
            
            var sortedCategories = Set(categories).sorted(by: { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending })
            if let otherIndex = sortedCategories.firstIndex(of: .other)
            {
                // Ensure "Other" is always last
                sortedCategories.move(fromOffsets: [otherIndex], toOffset: sortedCategories.count)
            }
            
            let actions = sortedCategories.map { category in
                let state: UIAction.State = (category == self.category) ? .on : .off
                let image = UIImage(systemName: category.filledSymbolName)?.withTintColor(category.tintColor, renderingMode: .alwaysOriginal)
                return UIAction(title: category.localizedName, image: image, state: state) { _ in
                    handler(category)
                }
            }
            
            return actions
        }
        catch
        {
            Logger.main.error("Failed to fetch categories. \(error.localizedDescription, privacy: .public)")
            
            return []
        }
    }
    
    @available(iOS 15, *)
    func prepareAppSorting()
    {
        if self.preferredAppSorting == .default && self.source == nil
        {
            // Only allow `default` sorting if source is non-nil.
            // Otherwise, fall back to `lastUpdated` sorting.
            self.preferredAppSorting = .lastUpdated
            
            // Don't update UserDefaults unless explicitly changed by user.
            // UserDefaults.shared.preferredAppSorting = .lastUpdated
        }
        
        let children = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            
            var sortingOptions = AppSorting.allCases
            if self.source == nil
            {
                // Only allow `default` sorting when source is non-nil.
                sortingOptions = sortingOptions.filter { $0 != .default }
            }
            
            let actions = sortingOptions.map { sorting in
                let state: UIMenuElement.State = (sorting == self.preferredAppSorting) ? .on : .off
                let action = UIAction(title: sorting.localizedName, image: nil, state: state) { action in
                    self.preferredAppSorting = sorting
                    UserDefaults.shared.preferredAppSorting = sorting // Update separately to save change.
                    
                    self.updateDataSource()
                }
                
                return action
            }
            
            completion(actions)
        }
        
        let sortMenu = UIMenu(title: NSLocalizedString("Sort by…", comment: ""), options: [.singleSelection], children: [children])
        let sortIcon = UIImage(systemName: "arrow.up.arrow.down")
        
        let sortButton = UIBarButtonItem(title: NSLocalizedString("Sort by…", comment: ""), image: sortIcon, primaryAction: nil, menu: sortMenu)
        self.sortButton = sortButton
        
        self.navigationItem.rightBarButtonItems = [sortButton]
    }
}

private extension BrowseViewController
{
    @IBAction func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        
        if let installedApp = app.installedApp, !installedApp.isUpdateAvailable
        {
            self.open(installedApp)
        }
        else
        {
            self.install(app, at: indexPath)
        }
    }
    
    func install(_ app: StoreApp, at indexPath: IndexPath)
    {
        let previousProgress = AppManager.shared.installationProgress(for: app)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        Task<Void, Never>(priority: .userInitiated) { @MainActor in
            if let installedApp = app.installedApp, installedApp.isUpdateAvailable
            {
                AppManager.shared.update(installedApp, presentingViewController: self, completionHandler: finish(_:))
            }
            else
            {
                await AppManager.shared.installAsync(app, presentingViewController: self, completionHandler: finish(_:))
            }
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        
        @MainActor
        func finish(_ result: Result<InstalledApp, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled): break // Ignore
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.opensErrorLog = true
                    toastView.show(in: self)
                    
                case .success: print("Installed app:", app.bundleIdentifier)
                }
                
                UIView.performWithoutAnimation {
                    if let indexPath = self.dataSource.fetchedResultsController.indexPath(forObject: app)
                    {
                        self.collectionView.reloadItems(at: [indexPath])
                    }
                    else
                    {
                        self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
                    }
                }
            }
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension BrowseViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let item = self.dataSource.item(at: indexPath)
        let itemID = item.globallyUniqueID ?? item.bundleIdentifier

        if let previousSize = self.cachedItemSizes[itemID]
        {
            return previousSize
        }
        
        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)
        
        let insets = (self.view.layoutMargins.left + self.view.layoutMargins.right)

        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width - insets)
        widthConstraint.isActive = true
        defer { widthConstraint.isActive = false }

        // Manually update cell width & layout so we can accurately calculate screenshot sizes.
        self.prototypeCell.frame.size.width = widthConstraint.constant
        self.prototypeCell.layoutIfNeeded()
        
        let itemSize = self.prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.cachedItemSizes[itemID] = itemSize
        return itemSize
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let app = self.dataSource.item(at: indexPath)
        let appViewController = AppViewController.makeAppViewController(app: app)
        
        // Fall back to presentingViewController.navigationController in case we're being used for search results.
        let navigationController = self.navigationController ?? self.presentingViewController?.navigationController
        navigationController?.pushViewController(appViewController, animated: true)
    }
}

extension BrowseViewController: UIViewControllerPreviewingDelegate
{
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        guard
            let indexPath = self.collectionView.indexPathForItem(at: location),
            let cell = self.collectionView.cellForItem(at: indexPath)
        else { return nil }
        
        previewingContext.sourceRect = cell.frame
        
        let app = self.dataSource.item(at: indexPath)
        
        let appViewController = AppViewController.makeAppViewController(app: app)
        return appViewController
    }
    
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        self.navigationController?.pushViewController(viewControllerToCommit, animated: true)
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
   
    let storyboard = UIStoryboard(name: "Main", bundle: .main)
    let browseViewController = storyboard.instantiateViewController(identifier: "browseViewController") { coder in
        BrowseViewController(source: nil, coder: coder)
    }
    
    let navigationController = UINavigationController(rootViewController: browseViewController)
    return navigationController
}
