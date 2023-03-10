//
//  SourcesDetailContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

@objc(AppBannerViewCell)
class AppBannerViewCell: UICollectionViewCell
{
    let bannerView: AppBannerView
    
    override init(frame: CGRect)
    {
        self.bannerView = AppBannerView(frame: .zero)
        
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        self.bannerView = AppBannerView(frame: .zero)
        
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView, pinningEdgesWith: .zero)
    }
}

extension SourcesDetailContentViewController
{
    private enum Section: Int
    {
        case news
        case apps
    }
    
    private enum ElementKind: String
    {
        case title
        case button
    }
}

class ButtonView: UICollectionReusableView
{
    let button: UIButton
    
//    var bottomSpacing: Double {
//        get { self.bottomConstraint.constant }
//        set { self.bottomConstraint.constant = newValue }
//    }
//    private var bottomConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect)
    {
        self.button = UIButton(type: .system)
        self.button.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: frame)
        
        self.addSubview(self.button)
        
//        self.bottomConstraint = self.bottomAnchor.constraint(equalTo: self.button.bottomAnchor)
        
        // Constrain to top, leading, trailing, but allow arbitrary bottom spacing.
        NSLayoutConstraint.activate([
//            self.bottomConstraint,
            self.button.topAnchor.constraint(equalTo: self.topAnchor),
            self.button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TitleView: UICollectionReusableView
{
    let label: UILabel
    
    override init(frame: CGRect)
    {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withSymbolicTraits(.traitBold)!
        let font = UIFont(descriptor: fontDescriptor, size: 0.0)
        
        self.label = UILabel(frame: .zero)
        
        super.init(frame: frame)
        
        self.label.font = font
        self.addSubview(self.label, pinningEdgesWith: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SourcesDetailContentViewController: UICollectionViewController
{
    let source: Source
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var newsDataSource = self.makeNewsDataSource()
    private lazy var appsDataSource = self.makeAppsDataSource()
        
    init(source: Source)
    {
        self.source = source
        
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.tintColor = self.source.tintColor
        self.collectionView.collectionViewLayout = self.makeLayout()
         
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: "NewsCell")
        self.collectionView.register(AppBannerViewCell.self, forCellWithReuseIdentifier: "AppCell")
        self.collectionView.register(TitleView.self, forSupplementaryViewOfKind: ElementKind.title.rawValue, withReuseIdentifier: ElementKind.title.rawValue)
        self.collectionView.register(ButtonView.self, forSupplementaryViewOfKind: ElementKind.button.rawValue, withReuseIdentifier: ElementKind.button.rawValue)
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
    }
    
    override func viewSafeAreaInsetsDidChange()
    {
        super.viewSafeAreaInsetsDidChange()
        
//        if let buttonView = self.collectionView.supplementaryView(forElementKind: ElementKind.button.rawValue, at: IndexPath(item: 0, section: Section.apps.rawValue)) as? ButtonView
//        {
//            buttonView.bottomSpacing = 8 + self.view.safeAreaInsets.bottom
//        }
    }
}

extension SourcesDetailContentViewController: CarolineContentViewController
{
    var scrollView: UIScrollView { self.collectionView }
}

private extension SourcesDetailContentViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layout = UICollectionViewCompositionalLayout { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let `self` = self, let section = Section(rawValue: sectionIndex) else { return nil }
            
            let inset = 20.0
            
            switch section
            {
            case .news:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(1))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupWidth = layoutEnvironment.container.contentSize.width - inset * 2
                let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(groupWidth), heightDimension: .estimated(1))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
//                let buttonAnchor = NSCollectionLayoutAnchor(edges: [.top, .trailing], absoluteOffset: CGPoint(x: 0, y: -(self.prototypeButton.bounds.height + 8)))
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(60), heightDimension: self.newsDataSource.itemCount == 0 ? .absolute(1) : .estimated(20))
                let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .bottomTrailing)
                
//                let showAllButton = NSCollectionLayoutSupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.showAllButton.rawValue, containerAnchor: buttonAnchor)
//                group.supplementaryItems = [showAllButton]
                
//                group.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 10, trailing: 20)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: inset, leading: inset, bottom: 4, trailing: inset)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.boundarySupplementaryItems = [sectionFooter]
                return layoutSection
                
            case .apps:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(88))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
                
                let titleSize = NSCollectionLayoutSize(widthDimension: .estimated(75), heightDimension: .estimated(40))
                let titleHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: titleSize, elementKind: ElementKind.title.rawValue, alignment: .topLeading)
                
                let buttonSize = NSCollectionLayoutSize(widthDimension: .estimated(60), heightDimension: self.appsDataSource.itemCount == 0 ? .absolute(1) : /*.estimated(20)*/ .absolute(68))
                let buttonHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: buttonSize, elementKind: ElementKind.button.rawValue, alignment: .bottomTrailing)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 15
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 15 /* independent of inset */, leading: inset, bottom: 4, trailing: inset)
                layoutSection.orthogonalScrollingBehavior = .none
                layoutSection.boundarySupplementaryItems = [titleHeader, buttonHeader]
                return layoutSection
            }
        }

        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>
    {
        let newsDataSource = self.newsDataSource as! RSTFetchedResultsCollectionViewDataSource<NSManagedObject>
        let appsDataSource = self.appsDataSource as! RSTFetchedResultsCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>
        
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<NSManagedObject, UIImage>(dataSources: [newsDataSource, appsDataSource])
        return dataSource
    }
    
    func makeNewsDataSource() -> RSTFetchedResultsCollectionViewDataSource<NewsItem>
    {
        let fetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NewsItem>
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(NewsItem.source), self.source)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \NewsItem.sortIndex, ascending: false)]
        
        let dataSource = RSTFetchedResultsCollectionViewDataSource(fetchRequest: fetchRequest, managedObjectContext: self.source.managedObjectContext ?? DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "NewsCell" }
        dataSource.liveFetchLimit = 5
        dataSource.cellConfigurationHandler = { (cell, newsItem, indexPath) in
            let cell = cell as! NewsCollectionViewCell
            
            cell.layoutMargins = .zero
            cell.contentView.layoutMargins = .zero
//            cell.contentView.layoutMargins.left = 0//self.view.layoutMargins.left
//            cell.contentView.layoutMargins.right = 0//self.view.layoutMargins.right
            
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
    
    func makeAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(StoreApp._source), self.source)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(StoreApp._source), ascending: true)]
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: self.source.managedObjectContext ?? DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.liveFetchLimit = 5
        dataSource.cellConfigurationHandler = { (cell, storeApp, indexPath) in
            let cell = cell as! AppBannerViewCell
            
//            cell.layoutMargins.left = self.view.layoutMargins.left
//            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = storeApp.tintColor
            
            cell.bannerView.iconImageView.isIndicatingActivity = true
            cell.bannerView.buttonLabel.isHidden = true
            cell.bannerView.alpha = 1.0
            
            cell.bannerView.configure(for: storeApp)
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.button.tintColor = storeApp.tintColor
            
            if storeApp.installedApp == nil
            {
                let buttonTitle = NSLocalizedString("Free", comment: "")
                cell.bannerView.button.setTitle(buttonTitle.uppercased(), for: .normal)
                cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Download %@", comment: ""), storeApp.name)
                cell.bannerView.button.accessibilityValue = buttonTitle
                
                let progress = AppManager.shared.installationProgress(for: storeApp)
                cell.bannerView.button.progress = progress
                
                if let versionDate = storeApp.latestSupportedVersion?.date, versionDate > Date()
                {
                    cell.bannerView.button.countdownDate = versionDate
                }
                else
                {
                    cell.bannerView.button.countdownDate = nil
                }
            }
            else
            {
                cell.bannerView.button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
                cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Open %@", comment: ""), storeApp.name)
                cell.bannerView.button.accessibilityValue = nil
                cell.bannerView.button.progress = nil
                cell.bannerView.button.countdownDate = nil
            }

            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
            
            if let progress = AppManager.shared.installationProgress(for: storeApp), progress.fractionCompleted < 1.0
            {
                cell.bannerView.button.progress = progress
            }
            else
            {
                cell.bannerView.button.progress = nil
            }
            
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
            let cell = cell as! AppBannerViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
        }
        
        return dataSource
    }
}

extension SourcesDetailContentViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath)
        
        let section = Section(rawValue: indexPath.section)!
        let kind = ElementKind(rawValue: kind)!
        switch (section, kind)
        {
        case (.news, _):
            let buttonView = headerView as! ButtonView
            buttonView.button.setTitle(NSLocalizedString("View All", comment: ""), for: .normal)
            buttonView.button.isHidden = (self.newsDataSource.itemCount == 0)
            
        case (.apps, .title):
            let titleView = headerView as! TitleView
            titleView.label.text = NSLocalizedString("Featured Apps", comment: "")
            
        case (.apps, .button):
            let buttonView = headerView as! ButtonView
            buttonView.button.setTitle(NSLocalizedString("View All Apps", comment: ""), for: .normal)
//            buttonView.bottomSpacing = 8 + self.view.safeAreaInsets.bottom // Add 20pts of spacing to bottom of collection view
            
            print("[ALTLog] Bottom Spacing:", self.view.safeAreaInsets.bottom)
            
        }
        
        return headerView
    }
}
