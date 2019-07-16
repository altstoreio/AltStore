//
//  BrowseCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

@objc class BrowseCollectionViewCell: UICollectionViewCell
{
    var imageNames: [String] = [] {
        didSet {
            self.dataSource.items = self.imageNames.map { $0 as NSString }
        }
    }
    private lazy var dataSource = self.makeDataSource()
    
    private lazy var imageSizes = [NSString: CGSize]()
    
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var developerLabel: UILabel!
    @IBOutlet var appIconImageView: UIImageView!
    @IBOutlet var actionButton: ProgressButton!
    @IBOutlet var subtitleLabel: UILabel!
    
    @IBOutlet private var screenshotsContentView: UIView!
    @IBOutlet private var screenshotsCollectionView: UICollectionView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.screenshotsCollectionView.delegate = self
        self.screenshotsCollectionView.dataSource = self.dataSource
        self.screenshotsCollectionView.prefetchDataSource = self.dataSource
        
        self.screenshotsContentView.layer.cornerRadius = 20
        self.screenshotsContentView.layer.masksToBounds = true
        
        self.update()
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
}

private extension BrowseCollectionViewCell
{
    func makeDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSString, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSString, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { (cell, screenshot, indexPath) in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { (imageName, indexPath, completion) in
            return BlockOperation {
                let image = UIImage(named: imageName as String)
                completion(image, nil)
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
        }
        
        return dataSource
    }
    
    private func update()
    {
        self.subtitleLabel.textColor = self.tintColor
        self.screenshotsContentView.backgroundColor = self.tintColor.withAlphaComponent(0.1)
    }
}

extension BrowseCollectionViewCell: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let imageURL = self.dataSource.item(at: indexPath)
        let dimensions = self.imageSizes[imageURL] ?? UIScreen.main.nativeBounds.size
        
        let aspectRatio = dimensions.width / dimensions.height
        
        let height = self.screenshotsCollectionView.bounds.height
        let width = (self.screenshotsCollectionView.bounds.height * aspectRatio).rounded(.down)
        
        let size = CGSize(width: width, height: height)
        return size
    }
}
