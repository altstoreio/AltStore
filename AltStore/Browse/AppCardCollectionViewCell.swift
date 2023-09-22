//
//  BrowseAppCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 9/21/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

class AppCardCollectionViewCell: UICollectionViewCell
{
    let bannerView = AppBannerView(frame: .zero)
    
    private let screenshotsCollectionView: UICollectionView
    
    private lazy var dataSource = self.makeDataSource()
    
    private var screenshots: [AppScreenshot] = [] {
        didSet {
            self.dataSource.items = self.screenshots
        }
    }
    
    override init(frame: CGRect) 
    {
        self.screenshotsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        
        super.init(frame: frame)
        
        self.screenshotsCollectionView.collectionViewLayout = self.makeLayout()
        self.screenshotsCollectionView.backgroundColor = nil
        
        self.contentView.addSubview(self.bannerView.backgroundEffectView, pinningEdgesWith: .zero)
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView)
        
        self.screenshotsCollectionView.translatesAutoresizingMaskIntoConstraints = false
        self.screenshotsCollectionView.dataSource = self.dataSource
        self.screenshotsCollectionView.prefetchDataSource = self.dataSource
        self.screenshotsCollectionView.register(AppScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.contentView.addSubview(self.screenshotsCollectionView)
        
        NSLayoutConstraint.activate([
            self.bannerView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.bannerView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.bannerView.heightAnchor.constraint(equalToConstant: 88),
            
            self.screenshotsCollectionView.topAnchor.constraint(equalTo: self.bannerView.bottomAnchor),
            self.screenshotsCollectionView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.screenshotsCollectionView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.screenshotsCollectionView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
            
            self.contentView.widthAnchor.constraint(equalTo: self.contentView.heightAnchor, multiplier: 1.09)
        ])
        
        self.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        self.screenshotsCollectionView.layoutMargins = self.layoutMargins
        
//        self.contentView.clipsToBounds = true
    }
//    
//    override func layoutMarginsDidChange() 
//    {
//        super.layoutMarginsDidChange()
//        
//        self.layoutMargins = self.bannerView.layoutMargins
//        
//    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
//        self.layer.cornerRadius = self.bannerView.layer.cornerRadius
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension AppCardCollectionViewCell
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .layoutMargins
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self else { return nil }
            
            let screenshots = self.screenshots
            let minimumSpacing = 4.0
            
//            // Determine if there is only enough room for one screenshot.
//            // If so, we special-case that layout to horizontally center the item.
//            let screenshotWidths = screenshots.map { screenshot -> Double in
//                var aspectRatio = screenshot.size ?? defaultAspectRatio
//                if aspectRatio.width > aspectRatio.height
//                {
//                    switch screenshot.deviceType
//                    {
//                    case .iphone:
//                        // Always rotate landscape iPhone screenshots regardless of horizontal size class.
//                        aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
//                        
//                    default: break
//                    }
//                }
//                
//                let screenshotWidth = layoutEnvironment.container.effectiveContentSize.height * (aspectRatio.width / aspectRatio.height)
//                return screenshotWidth
//            }
//            
//            let minimumContentWidth = screenshotWidths.prefix(2).reduce(0) { $0 + minimumSpacing + $1 }
//            let totalContentWidth = screenshotWidths.reduce(0) { $0 + minimumSpacing + $1 }
            
            var visibleScreenshots = 0.0
            var totalContentWidth = 0.0
            
            for screenshot in screenshots
            {
                var aspectRatio = screenshot.size ?? defaultAspectRatio
                if aspectRatio.width > aspectRatio.height
                {
                    switch screenshot.deviceType
                    {
                    case .iphone:
                        // Always rotate landscape iPhone screenshots regardless of horizontal size class.
                        aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                        
                    default: break
                    }
                }
                
                let screenshotWidth = (layoutEnvironment.container.effectiveContentSize.height * (aspectRatio.width / aspectRatio.height)).rounded(.up) // Rounding important
                let nextTotalWidth = screenshotWidth + totalContentWidth
                
                if nextTotalWidth > layoutEnvironment.container.effectiveContentSize.width
                {
                    print("Next Width Too Large:", nextTotalWidth)
                    break
                }
                
                visibleScreenshots += 1
                totalContentWidth = nextTotalWidth
            }
            
            print("Visible Screenshots: \(visibleScreenshots). Content Width: \(totalContentWidth). Env: \(layoutEnvironment.container.effectiveContentSize)")
            
            let itemWidth = layoutEnvironment.container.effectiveContentSize.height * (defaultAspectRatio.width / defaultAspectRatio.height)
            let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(itemWidth), heightDimension: .fractionalHeight(1.0))
            
//            print("Min Content: \(minimumContentWidth). Total Content: \(totalContentWidth). Container: \(layoutEnvironment.container.effectiveContentSize)")
            
            let items: [NSCollectionLayoutItem]
            
            let singleItem = NSCollectionLayoutItem(layoutSize: itemSize)
            items = [singleItem]
                        
//            if (totalContentWidth < layoutEnvironment.container.effectiveContentSize.width ||
//                minimumContentWidth > layoutEnvironment.container.effectiveContentSize.width)
//            {
//                // There is only enough room for one screenshot (or all of them)
//                
//                print("Single Item (or can only show one)")
//                
//                let singleItem = NSCollectionLayoutItem(layoutSize: itemSize)
//                items = [singleItem]
//            }
//            else
//            {
//                print("Multi Item")
//                
//                let leadingItem = NSCollectionLayoutItem(layoutSize: itemSize)
//                leadingItem.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: .flexible(0.0), top: nil, trailing: nil, bottom: nil)
//                
//                let trailingItem = NSCollectionLayoutItem(layoutSize: itemSize)
//                trailingItem.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: nil, top: nil, trailing: .flexible(0.0), bottom: nil)
//                
//                items = [leadingItem, trailingItem]
//            }
            
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: items)
            group.interItemSpacing = .flexible(minimumSpacing)
            
            if items.count == 1
            {
                // Horizontally-center items
                
                
                let contentWidth: Double
                
//                if minimumContentWidth < layoutEnvironment.container.effectiveContentSize.width
//                {
//                    // Full thing fits, so use total width
//                    contentWidth = totalContentWidth
//                }
//                else if let screenshotWidth = screenshotWidths.first
//                {
//                    // Only first item fits, so use that single width
//                    contentWidth = screenshotWidth
//                }
//                else
//                {
//                    // Handled by system calculations, so just in case.
//                    contentWidth = layoutEnvironment.container.effectiveContentSize.width
//                }
                contentWidth = totalContentWidth
                
                let insetWidth = (layoutEnvironment.container.effectiveContentSize.width - contentWidth) / (visibleScreenshots + 1)
                
                print("Difference: \(layoutEnvironment.container.effectiveContentSize.width - contentWidth). Inset width:", insetWidth)
                
                group.contentInsets.leading = (insetWidth - 1).rounded(.down) // Subtracting 1 important to avoid overflowing + clipping
                group.contentInsets.trailing = (insetWidth - 1).rounded(.down) // Yes, this must be set for 2 9:19.5 screenshots to look correct
            }
            
            let layoutSection = NSCollectionLayoutSection(group: group)
//            layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
//            layoutSection.interGroupSpacing = 10
            
            return layoutSection
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] (cell, screenshot, indexPath) in
            let cell = cell as! AppScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
                        
            if var aspectRatio = screenshot.size
            {
                if aspectRatio.width > aspectRatio.height
                {
                    switch screenshot.deviceType
                    {
                    case .iphone:
                        // Always rotate landscape iPhone screenshots regardless of horizontal size class.
                        aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                        
//                    case .ipad where self?.traitCollection.horizontalSizeClass == .compact:
//                        // Only rotate landscape iPad screenshots if we're in horizontally compact environment.
//                        aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                        
                    default: break
                    }
                }
                
                cell.aspectRatio = aspectRatio
                cell.isRounded = false
            }
            else
            {
                cell.aspectRatio = defaultAspectRatio
                cell.isRounded = true
            }
        }
        dataSource.prefetchHandler = { [weak self] (screenshot, indexPath, completionHandler) in
            let imageURL = screenshot.imageURL
//            let traits = self?.traitCollection
            return RSTAsyncBlockOperation() { (operation) in
                let request = ImageRequest(url: imageURL as URL, processors: [.screenshot(screenshot, traits: nil)]) // Don't provide traits to prevent rotating iPad
                ImagePipeline.shared.loadImage(with: request, progress: nil) { result in
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
            let cell = cell as! AppScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
}

extension AppCardCollectionViewCell
{
    func configure(for storeApp: StoreApp)
    {
        self.screenshots = storeApp.preferredScreenshots()
        
        self.bannerView.tintColor = storeApp.tintColor
        self.bannerView.configure(for: storeApp)
        
//        self.bannerView.subtitleLabel.numberOfLines = 0
        self.bannerView.subtitleLabel.text = storeApp.subtitle ?? storeApp.developerName
    }
}

#Preview(traits: .portrait) {
    DatabaseManager.shared.startSynchronously()
   
    
    let storyboard = UIStoryboard(name: "Main", bundle: .main)
    
    let fetchRequest = StoreApp.fetchRequest()
    
    let storeApp = try! DatabaseManager.shared.viewContext.fetch(fetchRequest).first!
    
//    let appScreenshotsViewController = storyboard.instantiateViewController(identifier: "appScreenshotsViewController") { coder in
//        AppScreenshotsViewController(app: storeApp, coder: coder)
//    }
    
    let collectionViewCell = AppCardCollectionViewCell(frame: .zero)
    collectionViewCell.translatesAutoresizingMaskIntoConstraints = false
    collectionViewCell.configure(for: storeApp)
    
//    collectionViewCell.contentView.widthAnchor.constraint(equalToConstant: 375).isActive = true
    
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
    view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collectionViewCell)
    
    NSLayoutConstraint.activate([
        collectionViewCell.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
        collectionViewCell.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        collectionViewCell.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100)
//        collectionViewCell.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//        collectionViewCell.heightAnchor.constraint(equalToConstant: 400),
        
//        view.widthAnchor.constraint(equalToConstant: 375)
    ])
        
    return view
}
