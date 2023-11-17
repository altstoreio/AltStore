//
//  FeaturedViewController.swift
//  AltStore
//
//  Created by Riley Testut on 11/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

extension UIAction.Identifier
{
    fileprivate static let showAllApps = Self("io.altstore.ShowAllApps")
}

class LargeIconCollectionViewCell: UICollectionViewCell
{
    let textLabel = UILabel(frame: .zero)
    let imageView = UIImageView(frame: .zero)
    
    override init(frame: CGRect)
    {
        self.textLabel.translatesAutoresizingMaskIntoConstraints = false
        self.textLabel.textColor = .white
        self.textLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.contentMode = .center
        self.imageView.tintColor = .white
        self.imageView.alpha = 0.4
        self.imageView.preferredSymbolConfiguration = .init(pointSize: 80)
        
        super.init(frame: frame)
        
        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerRadius = 16
        self.contentView.layer.cornerCurve = .continuous
        
        self.contentView.addSubview(self.textLabel)
        self.contentView.addSubview(self.imageView)
        
        NSLayoutConstraint.activate([
            self.textLabel.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
            self.textLabel.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor, constant: -4),
            
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -30),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor, constant: 0),
            self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor, constant: 0),
            self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FeaturedViewController
{
    // Open ended because each Source is it's own section
    private struct Section: RawRepresentable, Comparable
    {
        static let recentlyUpdated = Section(rawValue: 0)
        static let categories = Section(rawValue: 1)
        static let featured = Section(rawValue: 2)
        
        let rawValue: Int
        
        var isFeaturedAppsSection: Bool {
            return self.rawValue > Section.featured.rawValue
        }
        
        init(rawValue: Int)
        {
            self.rawValue = rawValue
        }
        
        static func <(lhs: Section, rhs: Section) -> Bool 
        {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    private enum ReuseID: String
    {
        case recent = "RecentCell"
        case category = "CategoryCell"
        case featuredApp = "FeaturedAppCell"
    }
    
    private enum ElementKind: String
    {
        case sectionHeader
        case sourceHeader
        case button
    }
}

class FeaturedViewController: UICollectionViewController
{
    private var categories: [StoreCategory] = [] {
        didSet {
            let items = self.categories.map { $0.rawValue as NSString }
            self.categoriesDataSource.items = items
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var recentlyUpdatedDataSource = self.makeRecentlyUpdatedDataSource()
    private lazy var categoriesDataSource = self.makeCategoriesDataSource()
    private lazy var featuredDataSource = self.makeFeaturedDataSource()
    private lazy var featuredAppsDataSource = self.makeFeaturedAppsDataSource()
    
    private var searchController: RSTSearchController!
    private var searchBrowseViewController: BrowseViewController!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Browse", comment: "")
        self.navigationItem.largeTitleDisplayMode = .always
        
        if #available(iOS 16, *)
        {
            //self.navigationItem.largeTitleDisplayMode = .inline
            self.navigationItem.preferredSearchBarPlacement = .automatic
            //self.navigationItem.rightBarButtonItems = [.fixedSpace(100), .flexibleSpace()]
        }
        
        self.collectionView.backgroundColor = .altBackground
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.recent.rawValue)
        self.collectionView.register(LargeIconCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.category.rawValue)
        self.collectionView.register(AppCardCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.featuredApp.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: ElementKind.sectionHeader.rawValue, withReuseIdentifier: ElementKind.sectionHeader.rawValue)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: ElementKind.sourceHeader.rawValue, withReuseIdentifier: ElementKind.sourceHeader.rawValue)
        self.collectionView.register(ButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue)
        
        self.collectionView.directionalLayoutMargins.leading = 15
        self.collectionView.directionalLayoutMargins.trailing = 15
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        self.searchBrowseViewController = storyboard.instantiateViewController(identifier: "browseViewController") { coder in
            let browseViewController = BrowseViewController(coder: coder)
            return browseViewController
        }
        
        self.searchController = RSTSearchController(searchResultsController: self.searchBrowseViewController)
        self.searchController.searchableKeyPaths = [#keyPath(StoreApp.name),
                                                    #keyPath(StoreApp.developerName),
                                                    #keyPath(StoreApp.subtitle),
                                                    #keyPath(StoreApp.bundleIdentifier)]
        self.searchController.searchHandler = { [weak searchBrowseViewController] (searchValue, _) in
            searchBrowseViewController?.predicate = searchValue.predicate
            return nil
        }
        
        self.navigationItem.searchController = self.searchController
        self.navigationItem.hidesSearchBarWhenScrolling = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(FeaturedViewController.didFetchSources(_:)), name: AppManager.didFetchSourceNotification, object: nil)
    }
    
    override func viewIsAppearing(_ animated: Bool) 
    {
        super.viewIsAppearing(animated)
        
        self.updateCategories()
    }
}

private extension FeaturedViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 0
        config.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self else { return nil }
            
            let section = Section(rawValue: sectionIndex)
            
            switch section
            {
            case .recentlyUpdated:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(88))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(88 * 2 + 8))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item, item]) // 2 items per group
                group.interItemSpacing = .fixed(8)
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                //layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sectionInset, bottom: 4, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.boundarySupplementaryItems = [titleHeader]
                layoutSection.contentInsets.bottom = 30
                return layoutSection
                
            case .categories:
                let spacing = 10.0
                
                let itemWidth = (layoutEnvironment.container.effectiveContentSize.width - spacing) / 2
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(itemWidth), heightDimension: .absolute(90))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(90))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item]) // 2 items per group
                group.interItemSpacing = .fixed(spacing)
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.boundarySupplementaryItems = [titleHeader]
                layoutSection.contentInsets.bottom = 30
                return layoutSection
                
            case .featured:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(0.0))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.boundarySupplementaryItems = [titleHeader]
                layoutSection.contentInsets.top = 0
                layoutSection.contentInsets.bottom = 0
                return layoutSection
                
            case _ where section.isFeaturedAppsSection:
                let itemHeight: NSCollectionLayoutDimension = if #available(iOS 17, *) { .uniformAcrossSiblings(estimate: 100) } else { .estimated(100) }
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: itemHeight)
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: itemHeight)
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                group.interItemSpacing = .fixed(10)
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sourceHeader.rawValue, alignment: .topLeading)
                
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(44), heightDimension: .estimated(20))
                let buttonHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .topTrailing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.boundarySupplementaryItems = [titleHeader, buttonHeader]
                layoutSection.contentInsets.top = 8
                layoutSection.contentInsets.bottom = 30
                return layoutSection
                
            default: return nil
            }
        }, configuration: config)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let categoriesDataSource = self.categoriesDataSource as! RSTArrayCollectionViewPrefetchingDataSource<StoreApp, UIImage>
        
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [self.recentlyUpdatedDataSource, categoriesDataSource, self.featuredDataSource, self.featuredAppsDataSource])
        return dataSource
    }
    
    func makeRecentlyUpdatedDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = StoreApp.visibleAppsPredicate
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \StoreApp.latestSupportedVersion?.date, ascending: false),
            NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
        ]
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in ReuseID.recent.rawValue }
        dataSource.liveFetchLimit = 10 // Show 10 most recently updated apps
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let cell = cell as! AppBannerCollectionViewCell
            cell.tintColor = storeApp.tintColor
            cell.contentView.backgroundColor = .altBackground
            
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.layoutMargins = .zero
                        
            // Explicitly set to false to ensure we're starting from a non-activity indicating state.
            // Otherwise, cell reuse can mess up some cached values.
            cell.bannerView.button.isIndicatingActivity = false
            
            cell.bannerView.configure(for: storeApp)
            
            if let versionDate = storeApp.latestSupportedVersion?.date
            {
                cell.bannerView.subtitleLabel.text = Date().relativeDateString(since: versionDate, dateFormatter: Date.mediumDateFormatter)
            }
            
            //cell.bannerView.button.addTarget(self, action: #selector(SourceDetailContentViewController.performAppAction(_:)), for: .primaryActionTriggered)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            cell.bannerView.button.tintColor = storeApp.tintColor

            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        dataSource.prefetchHandler = { (storeApp, indexPath, completion) -> Foundation.Operation? in
            return RSTAsyncBlockOperation { (operation) in
                storeApp.managedObjectContext?.perform {
                    ImagePipeline.shared.loadImage(with: storeApp.iconURL, progress: nil) { result in
                        guard !operation.isCancelled else { return operation.finish() }
                        
                        switch result
                        {
                        case .success(let response): completion(response.image, nil)
                        case .failure(let error): completion(nil, error)
                        }
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
            
            if let error
            {
                print("[ALTLog] Error loading source icon:", error)
            }
        }
        
        return dataSource
    }
    
    func makeCategoriesDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSString, UIImage>
    {
//        let fetchRequest = StoreApp.fetchRequest()
//        fetchRequest.resultType = .dictionaryResultType
//        fetchRequest.returnsDistinctResults = true
//        fetchRequest.propertiesToFetch = [#keyPath(StoreApp._category)]
//        //fetchRequest.returnsObjectsAsFaults = false
//        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp._category, ascending: true)]
        
//        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._category), cacheName: nil)
        
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSString, UIImage>(items: [])
        dataSource.cellIdentifierHandler = { _ in ReuseID.category.rawValue }
        //dataSource.liveFetchLimit = 1 // Show 1 cell per category
        dataSource.cellConfigurationHandler = { cell, rawCategory, indexPath in
            guard let category = StoreCategory(rawValue: rawCategory as String) else { return }
            
            let cell = cell as! LargeIconCollectionViewCell
            
//            var content = cell.defaultContentConfiguration()
//            content.text = category.localizedName
//            content.textProperties.font = UIFont.preferredFont(forTextStyle: .largeTitle)
//            cell.contentConfiguration = content
            
            cell.textLabel.text = category.localizedName
            cell.imageView.image = UIImage(systemName: category.symbolName)
            
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = category.tintColor
            background.cornerRadius = 16
            cell.backgroundConfiguration = background
        }
        
        return dataSource
        
//        let flattenedDataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [dataSource])
//        flattenedDataSource.shouldFlattenSections = true
//        return flattenedDataSource
    }
    
    func makeFeaturedDataSource() -> RSTDynamicCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let dataSource = RSTDynamicCollectionViewPrefetchingDataSource<StoreApp, UIImage>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 0 }
        return dataSource
    }
    
    func makeFeaturedAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = StoreApp.visibleAppsPredicate
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true), // Sort by Source first for grouping
            NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
            NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)
        ]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp.sourceIdentifier), cacheName: nil)
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.cellIdentifierHandler = { _ in ReuseID.featuredApp.rawValue }
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let cell = cell as! AppCardCollectionViewCell
            cell.configure(for: storeApp)
            cell.prefersPagingScreenshots = true
            
            cell.bannerView.sourceIconImageView.isHidden = true
        }
        
        return dataSource
    }
}

private extension FeaturedViewController
{
    func updateCategories()
    {
        let fetchRequest = NSFetchRequest(entityName: StoreApp.entity().name!) as NSFetchRequest<NSDictionary>
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.returnsDistinctResults = true
        fetchRequest.propertiesToFetch = [#keyPath(StoreApp._category)]
        fetchRequest.predicate = StoreApp.visibleAppsPredicate
        //fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp._category, ascending: true)]
        
        do
        {
            let dictionaries = try DatabaseManager.shared.viewContext.fetch(fetchRequest)
            
            // Keep nil values
            let categories = dictionaries.map { $0[#keyPath(StoreApp._category)] as? String? ?? nil }.map { rawCategory -> StoreCategory in
                guard let rawCategory else { return .other }
                return StoreCategory(rawValue: rawCategory) ?? .other
            }
            
            let sortedCategories = Set(categories).sorted(by: { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending })
            self.categories = sortedCategories
        }
        catch
        {
            Logger.main.error("Failed to update categories. \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension FeaturedViewController
{
    @objc func didFetchSources(_ notification: Notification)
    {
        DispatchQueue.main.async {
            self.updateCategories()
        }
    }
    
    @IBSegueAction
    func makeBrowseViewController(_ coder: NSCoder, sender: Any) -> UIViewController?
    {
        if let category = sender as? StoreCategory
        {
            let browseViewController = BrowseViewController(category: category, coder: coder)
            return browseViewController
        }
        else if let source = sender as? Source
        {
            let browseViewController = BrowseViewController(source: source, coder: coder)
            return browseViewController
        }
        else
        {
            let browseViewController = BrowseViewController(coder: coder)
            return browseViewController
        }
    }
    
    func showAllApps(for source: Source)
    {
        self.performSegue(withIdentifier: "showBrowseViewController", sender: source)
    }
}

extension FeaturedViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView 
    {
        let section = Section(rawValue: indexPath.section)
        
        switch kind
        {
        case ElementKind.sourceHeader.rawValue:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var content = UIListContentConfiguration.plainHeader()
            
            let indexPath = IndexPath(item: 0, section: indexPath.section)
            let storeApp = self.dataSource.item(at: indexPath) // Safe?
            content.text = storeApp.source?.name ?? NSLocalizedString("Unknown Source", comment: "")
            //content.textProperties.color = .label//.withAlphaComponent(0.7)
//            content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
//            content.textProperties.transform = .none
//            content.textProperties.alignment = .natural
            content.textProperties.numberOfLines = 1
            
            content.directionalLayoutMargins.leading = 0
            content.imageToTextPadding = 8
            content.imageProperties.reservedLayoutSize = CGSize(width: 26, height: 26)
            content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
            content.imageProperties.cornerRadius = 13
            
            if let iconURL = storeApp.source?.effectiveIconURL, #available(iOS 15, *)
            {
                ImagePipeline.shared.loadImage(with: iconURL) { result in
                    headerView.setNeedsUpdateConfiguration()
                }
                
                headerView.configurationUpdateHandler = { cell, state in
                    var content = content.updated(for: state)
                    
                    if let image = ImagePipeline.shared.cache[iconURL]
                    {
                        content.image = image.image
                    }
                    
                    cell.contentConfiguration = content
                }
            }
            else if #available(iOS 15, *)
            {
                headerView.configurationUpdateHandler = nil
            }
            
            return headerView
            
        case ElementKind.sectionHeader.rawValue:
            // Regular section header
            
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var content: UIListContentConfiguration = if #available(iOS 15, *) {
                .prominentInsetGroupedHeader()
            }
            else {
                .groupedHeader()
            }
            
            switch section
            {
            case .recentlyUpdated: content.text = NSLocalizedString("New & Updated", comment: "")
            case .categories: content.text = NSLocalizedString("Categories", comment: "")
            case .featured: content.text = NSLocalizedString("Featured", comment: "")
            default: break
            }
            
            headerView.contentConfiguration = content
            return headerView
            
        case ElementKind.button.rawValue where section.isFeaturedAppsSection:
            let buttonView = collectionView.dequeueReusableSupplementaryView(ofKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue, for: indexPath) as! ButtonCollectionReusableView
            
            let indexPath = IndexPath(item: 0, section: indexPath.section)
            let storeApp = self.dataSource.item(at: indexPath) // Safe?
            buttonView.button.setTitle(NSLocalizedString("See All", comment: ""), for: .normal)
            buttonView.button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
            buttonView.tintColor = storeApp.source?.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
            buttonView.button.contentEdgeInsets.bottom = 8
            
            buttonView.button.removeAction(identifiedBy: .showAllApps, for: .primaryActionTriggered)
            
            if let source = storeApp.source
            {
                let action = UIAction(identifier: .showAllApps) { [weak self] _ in
                    self?.showAllApps(for: source)
                }
                buttonView.button.addAction(action, for: .primaryActionTriggered)
            }
            
            return buttonView
            
        default: return UICollectionReusableView(frame: .zero)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) 
    {
        let section = Section(rawValue: indexPath.section)
        switch section
        {
        case _ where section.isFeaturedAppsSection: fallthrough
        case .recentlyUpdated:
            let storeApp = self.dataSource.item(at: indexPath)
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
            
        case .categories:
            let categoryIndexPath = IndexPath(item: indexPath.item, section: 0)
            let rawCategory = self.categoriesDataSource.item(at: categoryIndexPath)
            
            let category = StoreCategory(rawValue: rawCategory as String) ?? .other
            self.performSegue(withIdentifier: "showBrowseViewController", sender: category)
            
        default: break
        }
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let featuredViewController = FeaturedViewController(collectionViewLayout: UICollectionViewFlowLayout())
    
    AppManager.shared.fetchSources() { (result) in
        do
        {
            let (_, context) = try result.get()
            try context.save()
        }
        catch let error as NSError
        {
            Logger.main.error("Failed to fetch sources for preview. \(error.localizedDescription, privacy: .public)")
        }
    }
    
    AppManager.shared.updateKnownSources { result in
        Task {
            do
            {
                let knownSources = try result.get()
                
                let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                
                try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                    for source in knownSources.0
                    {
                        guard let sourceURL = source.sourceURL else { continue }
                        
                        taskGroup.addTask {
                            _ = try await AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context)
                        }
                    }
                }
                
                await context.performAsync {
                    try! context.save()
                }
            }
            catch
            {
                Logger.main.error("Failed to fetch known sources for preview. \(error.localizedDescription, privacy: .public)")
            }
        }
    }
        
    let navigationController = UINavigationController(rootViewController: featuredViewController)
    navigationController.navigationBar.prefersLargeTitles = true
    return navigationController
}
