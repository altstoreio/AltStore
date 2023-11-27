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

private extension UIMenu.Identifier
{
    static let appSortOrder = Self("io.altstore.AppSortOrder")
}

private extension UIAction.Identifier
{
    static let sortByName = Self("io.altstore.Sort.Name")
    static let sortByDeveloper = Self("io.altstore.Sort.Developer")
    static let sortByLastUpdated = Self("io.altstore.Sort.LastUpdated")
}

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
    
    var predicate: NSPredicate? {
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
        
        if let source = self.source
        {
            self.title = source.name
            
            let tintColor = source.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
            self.view.tintColor = tintColor
            
            let appearance = NavigationBarAppearance()
            appearance.configureWithTintColor(tintColor)
            appearance.configureWithDefaultBackground()
            
            let edgeAppearance = appearance.copy()
            edgeAppearance.configureWithTransparentBackground()
            
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = edgeAppearance
        }
        else if let category = self.category, #available(iOS 16, *)
        {
            self.title = category.localizedName
            
            let menu = UIMenu(children: [
                UIDeferredMenuElement.uncached { completion in
                    let actions = self.makeCategoryActions()
                    completion(actions)
                }
            ])
            
            self.navigationItem.titleMenuProvider = { _ in
                return menu
            }
        }
        
        if #available(iOS 15, *)
        {
            self.prepareAppSorting()
        }
        
        self.navigationItem.largeTitleDisplayMode = .never
        
        if #available(iOS 16, *)
        {
            self.navigationItem.preferredSearchBarPlacement = .inline
        }
        
        self.preparePipeline()
        
        self.updateDataSource()
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.update()
    }
}

private extension BrowseViewController
{
    func preparePipeline()
    {
        AppManager.shared.$updateSourcesResult
            .receive(on: RunLoop.main) // Delay to next run loop so we receive _current_ value (not previous value).
            .sink { result in
                self.update()
            }
            .store(in: &self.cancellables)
    }
    
    func makeFetchRequest() -> NSFetchRequest<StoreApp>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let predicate = StoreApp.visibleAppsPredicate
        
        if let source = self.source
        {
            let filterPredicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp._source), source)
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [filterPredicate, predicate])
        }
        else if let category = self.category
        {
            let filterPredicate = switch category {
            case .other: NSPredicate(format: "%K == %@ OR %K == nil", #keyPath(StoreApp._category), category.rawValue, #keyPath(StoreApp._category))
            default: NSPredicate(format: "%K == %@", #keyPath(StoreApp._category), category.rawValue)
            }
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [filterPredicate, predicate])
        }
        else
        {
            fetchRequest.predicate = predicate
        }
        
        switch self.preferredAppSorting
        {
        case .default:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
            ]
            
        case .name:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
            ]
            
        case .developer:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \StoreApp.developerName, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
            ]
            
        case .lastUpdated:
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \StoreApp.latestSupportedVersion?.date, ascending: false),
                NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
            ]
        }
        
        return fetchRequest
    }
    
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = self.makeFetchRequest()
        
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: context)
        dataSource.placeholderView = self.placeholderView
        dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
            let cell = cell as! AppCardCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            // Explicitly set to false to ensure we're starting from a non-activity indicating state.
            // Otherwise, cell reuse can mess up some cached values.
            cell.bannerView.button.isIndicatingActivity = false
            
            cell.configure(for: app)
            
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
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppCardCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
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
        
        self.dataSource.predicate = self.predicate
    }
    
    func updateSources()
    {
        AppManager.shared.updateAllSources { result in
            self.collectionView.refreshControl?.endRefreshing()
            
            guard case .failure(let error) = result else { return }
            
            DispatchQueue.main.async {
                let toastView = ToastView(error: error)
                toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                toastView.show(in: self)
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
        
        if let source = self.source
        {
            self.title = NSLocalizedString("All Apps", comment: "")
            self.navigationController?.navigationBar.tintColor = source.effectiveTintColor ?? .altPrimary
        }
        else if let category = self.category
        {
            self.title = category.localizedName
            self.navigationController?.navigationBar.tintColor = .altPrimary
        }
        else
        {
            self.title = NSLocalizedString("Browse", comment: "")
            self.navigationController?.navigationBar.tintColor = .altPrimary
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
            
            let sortedCategories = Set(categories).sorted(by: { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending })
            
            let actions = sortedCategories.map { category in
                let state: UIAction.State = (category == self.category) ? .on : .off
                return UIAction(title: category.localizedName, image: UIImage(systemName: category.symbolName), state: state) { _ in
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
        
        let sortMenu = UIMenu(title: NSLocalizedString("Sort by…", comment: ""), identifier: .appSortOrder, options: [.displayInline, .singleSelection], children: [children])
        let sortIcon = UIImage(systemName: "arrow.up.arrow.down")
        
        let sortButton = UIBarButtonItem(title: NSLocalizedString("Sort by…", comment: ""), image: sortIcon, primaryAction: nil, menu: sortMenu)
        self.sortButton = sortButton
        
        self.navigationItem.rightBarButtonItems = [sortButton, .flexibleSpace()] // flexibleSpace() required to prevent showing full search bar inline.
    }
}

private extension BrowseViewController
{
    @IBAction func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        
        if let installedApp = app.installedApp
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
        
        _ = AppManager.shared.install(app, presentingViewController: self) { (result) in
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
                
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        
        self.collectionView.reloadItems(at: [indexPath])
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
        self.navigationController?.pushViewController(appViewController, animated: true)
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
    navigationController.navigationBar.prefersLargeTitles = true
    return navigationController
}
