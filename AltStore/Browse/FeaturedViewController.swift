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
    fileprivate static let showSourceDetails = Self("io.altstore.ShowSourceDetails")
}

extension FeaturedViewController
{
    // Open-ended because each Source is its own section
    private struct Section: RawRepresentable, Equatable
    {
        static let recentlyUpdated = Section(rawValue: 0)
        static let categories = Section(rawValue: 1)
        static let featuredHeader = Section(rawValue: 2)
        
        let rawValue: Int
        
        var isFeaturedAppsSection: Bool {
            return self.rawValue > Section.featuredHeader.rawValue
        }
        
        init(rawValue: Int)
        {
            self.rawValue = rawValue
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
    private lazy var dataSource = self.makeDataSource()
    private lazy var recentlyUpdatedDataSource = self.makeRecentlyUpdatedDataSource()
    private lazy var categoriesDataSource = self.makeCategoriesDataSource()
    private lazy var featuredAppsDataSource = self.makeFeaturedAppsDataSource()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Browse", comment: "")
        
        let layout = Self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.recent.rawValue)
        self.collectionView.register(LargeIconCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.category.rawValue)
        self.collectionView.register(AppCardCollectionViewCell.self, forCellWithReuseIdentifier: ReuseID.featuredApp.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: ElementKind.sectionHeader.rawValue, withReuseIdentifier: ElementKind.sectionHeader.rawValue)
        self.collectionView.register(IconButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.sourceHeader.rawValue, withReuseIdentifier: ElementKind.sourceHeader.rawValue)
        self.collectionView.register(ButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue)
        
        self.collectionView.backgroundColor = .altBackground
        self.collectionView.directionalLayoutMargins.leading = 20
        self.collectionView.directionalLayoutMargins.trailing = 20
        
        self.navigationItem.largeTitleDisplayMode = .always
    }
}

private extension FeaturedViewController
{
    class func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 0 // Must be 0 for Section.featuredHeader
        config.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            let section = Section(rawValue: sectionIndex)
            
            let spacing = 10.0
            let interSectionSpacing = 30.0
            let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(100), heightDimension: .estimated(20))
            
            switch section
            {
            case .recentlyUpdated:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(AppBannerView.standardHeight))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(AppBannerView.standardHeight * 2 + spacing))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item, item]) // 2 items per group
                group.interItemSpacing = .fixed(spacing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = spacing
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.contentInsets.bottom = interSectionSpacing
                layoutSection.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                ]
                return layoutSection
                
            case .categories:
                let itemWidth = (layoutEnvironment.container.effectiveContentSize.width - spacing) / 2
                let itemHeight = 90.0
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item]) // 2 items per group
                group.interItemSpacing = .fixed(spacing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = spacing
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.contentInsets.bottom = interSectionSpacing
                layoutSection.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                ]
                return layoutSection
                
            case .featuredHeader:
                // We don't want to show any items, so set height to 1.0
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(1.0))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets.top = 0
                layoutSection.contentInsets.bottom = 0
                layoutSection.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sectionHeader.rawValue, alignment: .topLeading)
                ]
                return layoutSection
                
            case _ where section.isFeaturedAppsSection:
                let itemHeight: NSCollectionLayoutDimension = if #available(iOS 17, *) { .uniformAcrossSiblings(estimate: 350) } else { .estimated(350) }
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: itemHeight)
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: itemHeight)
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                group.interItemSpacing = .fixed(spacing)
                
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.sourceHeader.rawValue, alignment: .topLeading)
                
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(44), heightDimension: .estimated(20))
                let buttonHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .topTrailing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = spacing
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.contentInsets.top = 8
                layoutSection.contentInsets.bottom = interSectionSpacing
                layoutSection.boundarySupplementaryItems = [titleHeader, buttonHeader]
                return layoutSection
                
            default: return nil
            }
        }, configuration: config)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let featuredHeaderDataSource = RSTDynamicCollectionViewDataSource<StoreApp>()
        featuredHeaderDataSource.numberOfSectionsHandler = { 1 }
        featuredHeaderDataSource.numberOfItemsHandler = { _ in 0 }
        
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [self.recentlyUpdatedDataSource, self.categoriesDataSource, featuredHeaderDataSource, self.featuredAppsDataSource])
        dataSource.predicate = StoreApp.visibleAppsPredicate // Ensure we never accidentally show hidden apps
        return dataSource
    }
    
    func makeRecentlyUpdatedDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
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
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.layoutMargins = .zero
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: storeApp)
            
            if let versionDate = storeApp.latestSupportedVersion?.date
            {
                cell.bannerView.subtitleLabel.text = Date().relativeDateString(since: versionDate, dateFormatter: Date.mediumDateFormatter)
            }
            
            cell.bannerView.button.addTarget(self, action: #selector(FeaturedViewController.performAppAction), for: .primaryActionTriggered)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
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
        dataSource.prefetchCompletionHandler = { [weak dataSource] (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
            
            if let error, let dataSource
            {
                let app = dataSource.item(at: indexPath)
                Logger.main.debug("Failed to app icon from \(app.iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return dataSource
    }
    
    func makeCategoriesDataSource() -> RSTCompositeCollectionViewDataSource<StoreApp>
    {
        let knownCategories = StoreCategory.allCases.filter { $0 != .other }.map { $0.rawValue }
        
        let knownFetchRequest = StoreApp.fetchRequest()
        knownFetchRequest.predicate = NSPredicate(format: "%K IN %@", #keyPath(StoreApp._category), knownCategories)
        knownFetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp._category, ascending: true),
                                             NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                                             NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true)]
        
        let unknownFetchRequest = StoreApp.fetchRequest()
        unknownFetchRequest.predicate = StoreApp.otherCategoryPredicate
        unknownFetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp._category, ascending: true),
                                               NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true),
                                               NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true)]
        
        let knownController = NSFetchedResultsController(fetchRequest: knownFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._category), cacheName: nil)
        let knownDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: knownController)
        knownDataSource.liveFetchLimit = 1 // One app per category
        
        let unknownController = NSFetchedResultsController(fetchRequest: unknownFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        let unknownDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: unknownController)
        unknownDataSource.liveFetchLimit = 1
        
        // Use composite data source to ensure "Other" category is always last.
        let dataSource = RSTCompositeCollectionViewDataSource<StoreApp>(dataSources: [knownDataSource, unknownDataSource])
        dataSource.shouldFlattenSections = true // Combine into single section, with one StoreApp per category.
        dataSource.cellIdentifierHandler = { _ in ReuseID.category.rawValue }
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let category = storeApp.category ?? .other
            
            let cell = cell as! LargeIconCollectionViewCell
            cell.textLabel.text = category.localizedName
            cell.imageView.image = UIImage(systemName: category.symbolName)
            
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = category.tintColor
            background.cornerRadius = 16
            cell.backgroundConfiguration = background
        }
        
        return dataSource
    }
    
    func makeFeaturedAppsDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [
            // Sort by Source first to group into sections.
            NSSortDescriptor(keyPath: \StoreApp._source?.featuredSortID, ascending: true),
            
            // Show uninstalled apps first.
            // Sorting by StoreApp.installedApp crashes because InstalledApp does not respond to compare:
            // Instead, sort by StoreApp.installedApp.storeApp.source.sourceIdentifier, which will be either nil OR source ID.
            NSSortDescriptor(keyPath: \StoreApp.installedApp?.storeApp?.sourceIdentifier, ascending: true),
            
            // Show featured apps first.
            // Sorting by StoreApp.featuringSource crashes because Source does not respond to compare:
            // Instead, sort by StoreApp.featuringSource.identifier, which will be either nil OR source ID.
            NSSortDescriptor(keyPath: \StoreApp.featuringSource?.identifier, ascending: false),
            
            // Randomize order within sections.
            NSSortDescriptor(keyPath: \StoreApp.featuredSortID, ascending: true),
            
            // Sanity check to ensure stable ordering
            NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)
        ]
        
        let sourceHasRemainingAppsPredicate = NSPredicate(format:
            """
            SUBQUERY(%K, $app,
                ($app.%K != %@) AND ($app.%K == nil) AND (($app.%K == NO) OR ($app.%K == NO) OR ($app.%K == YES))
            ).@count > 0
            """,
                                                          #keyPath(StoreApp._source._apps),
                                                          #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID,
                                                          #keyPath(StoreApp.installedApp),
                                                          #keyPath(StoreApp.isPledgeRequired), #keyPath(StoreApp.isHiddenWithoutPledge), #keyPath(StoreApp.isPledged)
        )
        
        let primaryFetchRequest = fetchRequest.copy() as! NSFetchRequest<StoreApp>
        primaryFetchRequest.predicate = sourceHasRemainingAppsPredicate
        
        let primaryController = NSFetchedResultsController(fetchRequest: primaryFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._source.featuredSortID), cacheName: nil)
        let primaryDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: primaryController)
        primaryDataSource.liveFetchLimit = 5
        
        let secondaryFetchRequest = fetchRequest.copy() as! NSFetchRequest<StoreApp>
        secondaryFetchRequest.predicate = NSCompoundPredicate(notPredicateWithSubpredicate: sourceHasRemainingAppsPredicate)
        
        let secondaryController = NSFetchedResultsController(fetchRequest: secondaryFetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(StoreApp._source.featuredSortID), cacheName: nil)
        let secondaryDataSource = RSTFetchedResultsCollectionViewDataSource<StoreApp>(fetchedResultsController: secondaryController)
        secondaryDataSource.liveFetchLimit = 5
        
        // Ensure sources with no remaining apps always come last.
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<StoreApp, UIImage>(dataSources: [primaryDataSource, secondaryDataSource])
        dataSource.cellIdentifierHandler = { _ in ReuseID.featuredApp.rawValue }
        dataSource.cellConfigurationHandler = { cell, storeApp, indexPath in
            let cell = cell as! AppCardCollectionViewCell
            cell.configure(for: storeApp)
            cell.prefersPagingScreenshots = false
            
            cell.bannerView.button.addTarget(self, action: #selector(FeaturedViewController.performAppAction), for: .primaryActionTriggered)
            cell.bannerView.sourceIconImageView.isHidden = true
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
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
        dataSource.prefetchCompletionHandler = { [weak dataSource] (cell, image, indexPath, error) in
            let cell = cell as! AppCardCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
            
            if let error = error, let dataSource
            {
                let app = dataSource.item(at: indexPath)
                Logger.main.debug("Failed to app icon from \(app.iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return dataSource
    }
}

private extension FeaturedViewController
{
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
    
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        return sourceDetailViewController
    }
    
    func showAllApps(for source: Source)
    {
        self.performSegue(withIdentifier: "showBrowseViewController", sender: source)
    }
    
    func showSourceDetails(for source: Source)
    {
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
}

private extension FeaturedViewController
{
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let storeApp = self.dataSource.item(at: indexPath)
        
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
        
        if let installedApp = storeApp.installedApp, installedApp.isUpdateAvailable
        {
            AppManager.shared.update(installedApp, presentingViewController: self, completionHandler: finish(_:))
        }
        else
        {
            AppManager.shared.install(storeApp, presentingViewController: self, completionHandler: finish(_:))
        }
        
        UIView.performWithoutAnimation {
            self.collectionView.reloadItems(at: [indexPath])
        }
        
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
                    
                case .success:
                    Logger.main.info("Installed app \(storeApp.bundleIdentifier, privacy: .public) from FeaturedViewController.")
                }
                
                for indexPath in self.collectionView.indexPathsForVisibleItems
                {
                    // Only need to reload if it's still visible.
                    
                    let item = self.dataSource.item(at: indexPath)
                    guard item == storeApp else { continue }
                    
                    UIView.performWithoutAnimation {
                        self.collectionView.reloadItems(at: [indexPath])
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

extension FeaturedViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)
        
        switch kind
        {
        case ElementKind.sourceHeader.rawValue:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! IconButtonCollectionReusableView
            
            let indexPath = IndexPath(item: 0, section: indexPath.section)
            let storeApp = self.dataSource.item(at: indexPath)
            
            var content = UIListContentConfiguration.plainHeader()
            content.text = storeApp.source?.name ?? NSLocalizedString("Unknown Source", comment: "")
            content.textProperties.numberOfLines = 1
            
            content.directionalLayoutMargins.leading = 0
            content.imageToTextPadding = 8
            content.imageProperties.reservedLayoutSize = CGSize(width: 26, height: 26)
            content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
            content.imageProperties.cornerRadius = 13
            
            headerView.titleButton.setTitle(content.text, for: .normal)
            
            headerView.iconButton.backgroundColor = storeApp.source?.effectiveTintColor?.adjustedForDisplay
            headerView.iconButton.setImage(nil, for: .normal)
            
            if let iconURL = storeApp.source?.effectiveIconURL
            {
                ImagePipeline.shared.loadImage(with: iconURL) { result in
                    guard case .success(let image) = result else { return }

                    headerView.iconButton.backgroundColor = .white
                    headerView.iconButton.setImage(image.image, for: .normal)
                }
            }
            
            let buttons = [headerView.iconButton, headerView.titleButton]
            for button in buttons
            {
                button.removeAction(identifiedBy: .showSourceDetails, for: .primaryActionTriggered)
                
                if let source = storeApp.source
                {
                    let action = UIAction(identifier: .showSourceDetails) { [weak self] _ in
                        self?.showSourceDetails(for: source)
                    }
                    button.addAction(action, for: .primaryActionTriggered)
                }
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
            case .featuredHeader: content.text = NSLocalizedString("Featured", comment: "")
            default: break
            }
            
            content.directionalLayoutMargins.leading = .zero
            content.directionalLayoutMargins.trailing = .zero
            
            headerView.contentConfiguration = content
            return headerView
            
        case ElementKind.button.rawValue where section.isFeaturedAppsSection:
            let buttonView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! ButtonCollectionReusableView
            
            let indexPath = IndexPath(item: 0, section: indexPath.section)
            let storeApp = self.dataSource.item(at: indexPath)
            
            buttonView.tintColor = storeApp.source?.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
            
            buttonView.button.setTitle(NSLocalizedString("See All", comment: ""), for: .normal)
            buttonView.button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
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
        let storeApp = self.dataSource.item(at: indexPath)
        
        let section = Section(rawValue: indexPath.section)
        switch section
        {
        case _ where section.isFeaturedAppsSection: fallthrough
        case .recentlyUpdated:
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
            
        case .categories:
            let category = storeApp.category ?? .other
            self.performSegue(withIdentifier: "showBrowseViewController", sender: category)
            
        default: break
        }
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let featuredViewController = storyboard.instantiateViewController(identifier: "featuredViewController")
    
    let navigationController = UINavigationController(rootViewController: featuredViewController)
    navigationController.navigationBar.prefersLargeTitles = true
    navigationController.modalPresentationStyle = .fullScreen
    
    let viewController = UIViewController()
    
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
                
                await MainActor.run {
                    viewController.present(navigationController, animated: true)
                }
            }
            catch
            {
                Logger.main.error("Failed to fetch known sources for preview. \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    return viewController
}
