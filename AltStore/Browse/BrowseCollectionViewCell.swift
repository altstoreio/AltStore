//
//  BrowseCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

import Nuke

@objc class BrowseCollectionViewCell: UICollectionViewCell
{
    var imageURLs: [URL] = [] {
        didSet {
            self.dataSource.items = self.imageURLs as [NSURL]
        }
    }
    private lazy var dataSource = self.makeDataSource()
    
    @IBOutlet var bannerView: AppBannerView!
    @IBOutlet var subtitleLabel: UILabel!
    
    @IBOutlet private(set) var screenshotsCollectionView: UICollectionView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.preservesSuperviewLayoutMargins = true
        
        // Must be registered programmatically, not in BrowseCollectionViewCell.xib, or else it'll throw an exception 🤷‍♂️.
        self.screenshotsCollectionView.register(ScreenshotCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.screenshotsCollectionView.delegate = self
        self.screenshotsCollectionView.dataSource = self.dataSource
        self.screenshotsCollectionView.prefetchDataSource = self.dataSource
    }
}

private extension BrowseCollectionViewCell
{
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { (cell, screenshot, indexPath) in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { (imageURL, indexPath, completionHandler) in
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL as URL, progress: nil, completion: { (response, error) in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    if let image = response?.image
                    {
                        completionHandler(image, nil)
                    }
                    else
                    {
                        completionHandler(nil, error)
                    }
                })
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! ScreenshotCollectionViewCell
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

extension BrowseCollectionViewCell: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        // Assuming 9.0 / 16.0 ratio for now.
        let aspectRatio: CGFloat = 9.0 / 16.0

        let itemHeight = collectionView.bounds.height
        let itemWidth = itemHeight * aspectRatio

        let size = CGSize(width: itemWidth.rounded(.down), height: itemHeight.rounded(.down))
        return size
    }
}
