//
//  AppScreenshotsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

class AppScreenshotsViewController: UICollectionViewController
{
    let app: StoreApp
    
    private lazy var dataSource = self.makeDataSource()
    
    init?(app: StoreApp, coder: NSCoder)
    {
        self.app = app
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.showsHorizontalScrollIndicator = false
        
        // Allow parent background color to show through.
        self.collectionView.backgroundColor = nil
        
        // Match the parent table view margins.
        self.collectionView.directionalLayoutMargins.top = 0
        self.collectionView.directionalLayoutMargins.bottom = 0
        self.collectionView.directionalLayoutMargins.leading = 20
        self.collectionView.directionalLayoutMargins.trailing = 20
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.register(AppScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
    }
}

private extension AppScreenshotsViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .layoutMargins
        
        let preferredHeight = 400.0
        let estimatedWidth = preferredHeight * (AppScreenshot.defaultAspectRatio.width / AppScreenshot.defaultAspectRatio.height)
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [dataSource] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            let screenshotWidths = dataSource.items.map { screenshot in
                var aspectRatio = screenshot.size ?? AppScreenshot.defaultAspectRatio
                if aspectRatio.width > aspectRatio.height
                {
                    aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                }
                
                let screenshotWidth = (preferredHeight * (aspectRatio.width / aspectRatio.height)).rounded()
                return screenshotWidth
            }
            
            let smallestWidth = screenshotWidths.sorted().first
            let itemWidth = smallestWidth ?? estimatedWidth // Use smallestWidth to ensure we never overshoot an item when paging.
            
            let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(itemWidth), heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(itemWidth), heightDimension: .absolute(preferredHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            let layoutSection = NSCollectionLayoutSection(group: group)
            layoutSection.interGroupSpacing = 10
            layoutSection.orthogonalScrollingBehavior = .groupPaging
            
            return layoutSection
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>
    {
        let screenshots = self.app.preferredScreenshots()
        
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<AppScreenshot, UIImage>(items: screenshots)
        dataSource.cellConfigurationHandler = { [weak self] (cell, screenshot, indexPath) in
            let cell = cell as! AppScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = true
            cell.setImage(nil)
            
            var aspectRatio = screenshot.size ?? AppScreenshot.defaultAspectRatio
            if aspectRatio.width > aspectRatio.height
            {
                switch screenshot.deviceType
                {
                case .iphone:
                    // Always rotate landscape iPhone screenshots regardless of horizontal size class.
                    aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                    
                case .ipad where self?.traitCollection.horizontalSizeClass == .compact:
                    // Only rotate landscape iPad screenshots if we're in horizontally compact environment.
                    aspectRatio = CGSize(width: aspectRatio.height, height: aspectRatio.width)
                    
                default: break
                }
            }
            
            cell.aspectRatio = aspectRatio
        }
        dataSource.prefetchHandler = { (screenshot, indexPath, completionHandler) in
            let imageURL = screenshot.imageURL
            return RSTAsyncBlockOperation() { (operation) in
                let request = ImageRequest(url: imageURL)
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
            cell.setImage(image)
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
}

extension AppScreenshotsViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let screenshot = self.dataSource.item(at: indexPath)
        
        let previewViewController = PreviewAppScreenshotsViewController(app: self.app)
        previewViewController.currentScreenshot = screenshot
        
        let navigationController = UINavigationController(rootViewController: previewViewController)
        navigationController.modalPresentationStyle = .fullScreen
        self.present(navigationController, animated: true)
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let fetchRequest = StoreApp.fetchRequest()
    let storeApp = try! DatabaseManager.shared.viewContext.fetch(fetchRequest).first!
    
    let storyboard = UIStoryboard(name: "Main", bundle: .main)
    let appViewConttroller = storyboard.instantiateViewController(withIdentifier: "appViewController") as! AppViewController
    appViewConttroller.app = storeApp
    
    let navigationController = UINavigationController(rootViewController: appViewConttroller)
    return navigationController
}
