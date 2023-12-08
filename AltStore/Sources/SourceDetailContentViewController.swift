//
//  SourcesDetailContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices

import AltStoreCore
import Roxas

import Nuke

private let sectionInset = 20.0

extension SourceDetailContentViewController
{
    private enum Section: Int
    {
        case news
        case featuredApps
        case about
    }
    
    private enum ElementKind: String
    {
        case title
        case button
    }
}

class SourceDetailContentViewController: UICollectionViewController
{
    let source: Source
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var newsDataSource = self.makeNewsDataSource()
    private lazy var appsDataSource = self.makeAppsDataSource()
    private lazy var aboutDataSource = self.makeAboutDataSource()
    
    override var collectionViewLayout: UICollectionViewCompositionalLayout {
        return self.collectionView.collectionViewLayout as! UICollectionViewCompositionalLayout
    }
            
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.backgroundColor = .altBackground
        
        let collectionViewLayout = self.makeLayout(source: self.source)
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: "NewsCell")
        self.collectionView.register(TitleCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.title.rawValue, withReuseIdentifier: ElementKind.title.rawValue)
        self.collectionView.register(ButtonCollectionReusableView.self, forSupplementaryViewOfKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue)
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
    }
    
    override func viewSafeAreaInsetsDidChange()
    {
        super.viewSafeAreaInsetsDidChange()
        
        // Add sectionInset to safeAreaInsets.bottom.
        self.collectionView.contentInset = UIEdgeInsets(top: sectionInset, left: 0, bottom: self.view.safeAreaInsets.bottom + sectionInset, right: 0)
    }
}

private extension SourceDetailContentViewController
{
    func makeLayout(source: Source) -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.interSectionSpacing = 10
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
                        
            switch section
            {
            case .news:
                guard !source.newsItems.isEmpty else { return nil }
                
                // Underestimate height to prevent jumping size abruptly.
                let heightDimension: NSCollectionLayoutDimension = if #available(iOS 17, *) { .uniformAcrossSiblings(estimate: 50) } else { .estimated(50) }
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: heightDimension)
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupWidth = layoutEnvironment.container.contentSize.width - sectionInset * 2
                let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(groupWidth), heightDimension: heightDimension)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(60), heightDimension: .estimated(20))
                let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .bottomTrailing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sectionInset, bottom: 4, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.boundarySupplementaryItems = [sectionFooter]
                return layoutSection
                
            case .featuredApps:
                // Always show Featured Apps section, even if there are no apps.
                // guard !source.effectiveFeaturedApps.isEmpty else { return nil }
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(88))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.title.rawValue, alignment: .topLeading)
                
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(60), heightDimension: .estimated(20))
                let buttonHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .bottomTrailing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 15
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 15 /* independent of sectionInset */, leading: sectionInset, bottom: 4, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.boundarySupplementaryItems = [titleHeader, buttonHeader]
                return layoutSection
                
            case .about:
                guard source.localizedDescription != nil else { return nil }
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(200))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.title.rawValue, alignment: .topLeading)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 15 /* independent of sectionInset */, leading: sectionInset, bottom: 0, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.boundarySupplementaryItems = [titleHeader]
                return layoutSection
            }
        }, configuration: layoutConfig)

        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>
    {
        let newsDataSource = self.newsDataSource as! RSTFetchedResultsCollectionViewDataSource<NSManagedObject>
        let appsDataSource = self.appsDataSource as! RSTArrayCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>
        
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>(dataSources: [newsDataSource, appsDataSource, self.aboutDataSource])
        return dataSource
    }
    
    func makeNewsDataSource() -> RSTFetchedResultsCollectionViewDataSource<NewsItem>
    {
        let fetchRequest = NewsItem.sortedFetchRequest(for: self.source)
        
        let context = self.source.managedObjectContext ?? DatabaseManager.shared.viewContext
        let dataSource = RSTFetchedResultsCollectionViewDataSource(fetchRequest: fetchRequest, managedObjectContext: context)
        dataSource.liveFetchLimit = 5
        dataSource.cellIdentifierHandler = { _ in "NewsCell" }
        dataSource.cellConfigurationHandler = { (cell, newsItem, indexPath) in
            let cell = cell as! NewsCollectionViewCell
            
            // For some reason, setting cell.layoutMargins = .zero does not update cell.contentView.layoutMargins.
            cell.layoutMargins = .zero
            cell.contentView.layoutMargins = .zero
            
            cell.titleLabel.text = newsItem.title
            cell.captionLabel.text = newsItem.caption
            cell.contentBackgroundView.backgroundColor = newsItem.tintColor
            
            cell.imageView.image = nil
            cell.imageView.isHidden = true
            
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = (cell.titleLabel.text ?? "") + ". " + (cell.captionLabel.text ?? "")
            
            if newsItem.storeApp != nil || newsItem.externalURL != nil
            {
                cell.accessibilityTraits.insert(.button)
            }
            else
            {
                cell.accessibilityTraits.remove(.button)
            }
        }
        
        return dataSource
    }
    
    func makeAppsDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let featuredApps = self.source.effectiveFeaturedApps
        let limitedFeaturedApps = Array(featuredApps.prefix(5))
        
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<StoreApp, UIImage>(items: limitedFeaturedApps)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.predicate = StoreApp.visibleAppsPredicate
        dataSource.cellConfigurationHandler = { [weak self] (cell, storeApp, indexPath) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.tintColor = storeApp.tintColor
            
            // For some reason, setting cell.layoutMargins = .zero does not update cell.contentView.layoutMargins.
            cell.layoutMargins = .zero
            cell.contentView.layoutMargins = .zero
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: storeApp, showSourceIcon: false)
            
            cell.bannerView.button.tintColor = storeApp.tintColor
            cell.bannerView.button.addTarget(self, action: #selector(SourceDetailContentViewController.performAppAction(_:)), for: .primaryActionTriggered)
            
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
                Logger.main.debug("Failed to fetch app icon from \(app.iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
            }
        }
        
        return dataSource
    }
    
    func makeAboutDataSource() -> RSTDynamicCollectionViewDataSource<NSManagedObject>
    {
        let dataSource = RSTDynamicCollectionViewDataSource<NSManagedObject>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { [source] _ in source.localizedDescription == nil ? 0 : 1 }
        dataSource.cellIdentifierHandler = { _ in "AboutCell" }
        dataSource.cellConfigurationHandler = { [source] (cell, _, indexPath) in
            let cell = cell as! TextViewCollectionViewCell
            cell.contentView.layoutMargins = .zero // Fixes incorrect margins if not initially on screen.
            cell.textView.text = source.localizedDescription
            cell.textView.isCollapsed = false
            cell.textView.backgroundColor = .altBackground
        }
        
        return dataSource
    }
}

private extension SourceDetailContentViewController
{
    @objc func viewAllNews()
    {
        self.performSegue(withIdentifier: "showAllNews", sender: nil)
    }
    
    @objc func viewAllApps()
    {
        self.performSegue(withIdentifier: "showAllApps", sender: nil)
    }
    
    @IBSegueAction
    func makeNewsViewController(_ coder: NSCoder) -> UIViewController?
    {
        let newsViewController = NewsViewController(source: self.source, coder: coder)
        return newsViewController
    }
    
    @IBSegueAction
    func makeBrowseViewController(_ coder: NSCoder) -> UIViewController?
    {
        let browseViewController = BrowseViewController(source: self.source, coder: coder)
        return browseViewController
    }
}

extension SourceDetailContentViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let supplementaryView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath)
        
        let section = Section(rawValue: indexPath.section)!
        let kind = ElementKind(rawValue: kind)!
        switch (section, kind)
        {
        case (.news, _):
            let buttonView = supplementaryView as! ButtonCollectionReusableView
            buttonView.button.setTitle(NSLocalizedString("View All", comment: ""), for: .normal)
            
            buttonView.button.removeTarget(self, action: nil, for: .primaryActionTriggered)
            buttonView.button.addTarget(self, action: #selector(SourceDetailContentViewController.viewAllNews), for: .primaryActionTriggered)
            
        case (.featuredApps, .title):
            let titleView = supplementaryView as! TitleCollectionReusableView
            titleView.label.text = NSLocalizedString("Featured Apps", comment: "")
            
        case (.featuredApps, .button):
            let buttonView = supplementaryView as! ButtonCollectionReusableView
            buttonView.button.setTitle(NSLocalizedString("View All Apps", comment: ""), for: .normal)
            
            buttonView.button.removeTarget(self, action: nil, for: .primaryActionTriggered)
            buttonView.button.addTarget(self, action: #selector(SourceDetailContentViewController.viewAllApps), for: .primaryActionTriggered)
            
        case (.about, _):
            let titleView = supplementaryView as! TitleCollectionReusableView
            titleView.label.text = NSLocalizedString("About", comment: "")
        }
        
        return supplementaryView
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let section = Section(rawValue: indexPath.section)!
        let item = self.dataSource.item(at: indexPath)
        
        switch (section, item)
        {
        case (.news, let newsItem as NewsItem):
            if let externalURL = newsItem.externalURL
            {
                let safariViewController = SFSafariViewController(url: externalURL)
                safariViewController.preferredControlTintColor = newsItem.tintColor
                self.present(safariViewController, animated: true, completion: nil)
            }
            else if let storeApp = newsItem.storeApp
            {
                let appViewController = AppViewController.makeAppViewController(app: storeApp)
                self.navigationController?.pushViewController(appViewController, animated: true)
            }
            
        case (.featuredApps, let storeApp as StoreApp):
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
            
        default: break
        }
    }
}

private extension SourceDetailContentViewController
{
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let storeApp = self.dataSource.item(at: indexPath) as! StoreApp
        
        if let installedApp = storeApp.installedApp, !installedApp.isUpdateAvailable
        {
            self.open(installedApp)
        }
        else
        {
            sender.isIndicatingActivity = true
            
            Task<Void, Never> {
                await self.addSourceThenDownloadApp(storeApp)
                sender.isIndicatingActivity = false
            }
        }
    }
    
    func addSourceThenDownloadApp(_ storeApp: StoreApp) async
    {
        do
        {
            let isAdded = try await self.source.isAdded
            if !isAdded
            {
                let message = String(format: NSLocalizedString("You must add this source before you can install apps from it.\n\n“%@” will begin downloading once it has been added.", comment: ""), storeApp.name)
                try await AppManager.shared.add(self.source, message: message, presentingViewController: self)
            }
            
            do
            {
                try await self.downloadApp(storeApp)
            }
            catch is CancellationError {}
            catch
            {
                let toastView = ToastView(error: error)
                toastView.opensErrorLog = true
                toastView.show(in: self)
            }
        }
        catch is CancellationError {}
        catch
        {
            await self.presentAlert(title: NSLocalizedString("Unable to Add Source", comment: ""), message: error.localizedDescription)
        }
        
        self.collectionView.reloadSections([Section.featuredApps.rawValue])
    }
    
    @MainActor
    func downloadApp(_ storeApp: StoreApp) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let installedApp = storeApp.installedApp, installedApp.isUpdateAvailable
            {
                AppManager.shared.update(installedApp, presentingViewController: self) { result in
                    continuation.resume(with: result.map { _ in () })
                }
            }
            else
            {
                AppManager.shared.install(storeApp, presentingViewController: self) { result in
                    continuation.resume(with: result.map { _ in () })
                }
            }
            
            UIView.performWithoutAnimation {
                guard let index = self.appsDataSource.items.firstIndex(of: storeApp) else {
                    self.collectionView.reloadSections([Section.featuredApps.rawValue])
                    return
                }
                
                let indexPath = IndexPath(item: index, section: Section.featuredApps.rawValue)
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension SourceDetailContentViewController: ScrollableContentViewController
{
    var scrollView: UIScrollView { self.collectionView }
}
