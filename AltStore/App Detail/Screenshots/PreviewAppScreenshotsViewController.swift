//
//  PreviewAppScreenshotsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/19/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

class PreviewAppScreenshotsViewController: UICollectionViewController
{
    let app: StoreApp
    
    var currentScreenshot: AppScreenshot?
    
    private lazy var dataSource = self.makeDataSource()
    
    init(app: StoreApp)
    {
        self.app = app
        
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let tintColor = self.app.tintColor ?? .altPrimary
        self.navigationController?.view.tintColor = tintColor
        
        self.view.backgroundColor = .systemBackground
        self.collectionView.backgroundColor = nil
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.directionalLayoutMargins.leading = 20
        self.collectionView.directionalLayoutMargins.trailing = 20
        
        self.collectionView.preservesSuperviewLayoutMargins = true
        self.collectionView.insetsLayoutMarginsFromSafeArea = true
        
        self.collectionView.alwaysBounceVertical = false
        self.collectionView.register(AppScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        let doneButton = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismissPreview()
        })
        self.navigationItem.rightBarButtonItem = doneButton
        
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(PreviewAppScreenshotsViewController.dismissPreview))
        swipeGestureRecognizer.direction = .down
        self.view.addGestureRecognizer(swipeGestureRecognizer)
    }
    
    override func viewIsAppearing(_ animated: Bool)
    {
        super.viewIsAppearing(animated)
        
        if let screenshot = self.currentScreenshot, let index = self.dataSource.items.firstIndex(of: screenshot)
        {
            let indexPath = IndexPath(item: index, section: 0)
            self.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
    }
}

private extension PreviewAppScreenshotsViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .none
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self else { return nil }
            
            let contentInsets = self.collectionView.directionalLayoutMargins
            let groupWidth = layoutEnvironment.container.contentSize.width - (contentInsets.leading + contentInsets.trailing)
            let groupHeight = layoutEnvironment.container.contentSize.height - (contentInsets.top + contentInsets.bottom)
                        
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(groupWidth), heightDimension: .absolute(groupHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            let layoutSection = NSCollectionLayoutSection(group: group)
            layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
            layoutSection.interGroupSpacing = 10
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

private extension PreviewAppScreenshotsViewController
{
    @objc func dismissPreview()
    {
        self.dismiss(animated: true)
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let fetchRequest = StoreApp.fetchRequest()
    let storeApp = try! DatabaseManager.shared.viewContext.fetch(fetchRequest).first!
    
    let previewViewController = PreviewAppScreenshotsViewController(app: storeApp)
    
    let navigationController = UINavigationController(rootViewController: previewViewController)
    return navigationController
}
