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
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.tintColor = .white
        self.imageView.alpha = 0.4
        
        super.init(frame: frame)
        
        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerRadius = 16
        self.contentView.layer.cornerCurve = .continuous
        
        self.contentView.addSubview(self.textLabel)
        self.contentView.addSubview(self.imageView)
        
        NSLayoutConstraint.activate([
            self.textLabel.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.textLabel.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
            
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -30),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor, constant: -15),
            self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor),
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
    }
    
    private enum ElementKind: String
    {
        case sectionHeader
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
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Browse", comment: "")
        self.navigationItem.largeTitleDisplayMode = .always
        
        self.collectionView.backgroundColor = .altBackground
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.recent.rawValue)
        self.collectionView.register(LargeIconCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.category.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        
        self.collectionView.directionalLayoutMargins.leading = 20
        self.collectionView.directionalLayoutMargins.trailing = 20
        
        self.navigationItem.searchController = self.recentlyUpdatedDataSource.searchController
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
        config.interSectionSpacing = 30
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
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                //layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sectionInset, bottom: 4, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.boundarySupplementaryItems = [titleHeader]
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
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.boundarySupplementaryItems = [titleHeader]
                return layoutSection
                
            default: return nil
            }
            
//            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
//            configuration.showsSeparators = true
//            configuration.separatorConfiguration.color = UIColor(resource: .gradientBottom).withAlphaComponent(0.7) //.white.withAlphaComponent(0.8)
//            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 20
//            configuration.backgroundColor = .clear
//            
//            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
//            
////            layoutSection.contentInsets.top = 15
//            
//            return layoutSection
        }, configuration: config)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let categoriesDataSource = self.categoriesDataSource as! RSTArrayCollectionViewPrefetchingDataSource<StoreApp, UIImage>
        
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [self.recentlyUpdatedDataSource, categoriesDataSource])
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
}

extension FeaturedViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView 
    {
        let section = Section(rawValue: indexPath.section)
        
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader, for: indexPath) as! UICollectionViewListCell
        
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
        default: break
        }
        
        headerView.contentConfiguration = content
        return headerView
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
        
    let navigationController = UINavigationController(rootViewController: featuredViewController)
    navigationController.navigationBar.prefersLargeTitles = true
    return navigationController
}
