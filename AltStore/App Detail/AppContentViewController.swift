//
//  AppContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltStoreCore
import AltSign
import Roxas

import Nuke

extension AppContentViewController
{
    private enum Row: Int, CaseIterable
    {
        case subtitle
        case screenshots
        case description
        case versionDescription
        case permissions
    }
}

class AppContentViewController: UITableViewController
{
    var app: StoreApp!
    
    private lazy var screenshotsDataSource = self.makeScreenshotsDataSource()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    private lazy var byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        return formatter
    }()
    
    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var descriptionTextView: CollapsingTextView!
    @IBOutlet private var versionDescriptionTextView: CollapsingTextView!
    @IBOutlet private var versionLabel: UILabel!
    @IBOutlet private var versionDateLabel: UILabel!
    @IBOutlet private var sizeLabel: UILabel!
    
    @IBOutlet private var screenshotsCollectionView: UICollectionView!
    
    @IBOutlet private(set) var appDetailCollectionViewController: AppDetailCollectionViewController!
    @IBOutlet private var appDetailCollectionViewHeightConstraint: NSLayoutConstraint!
    
    var preferredScreenshotSize: CGSize? {        
        let layout = self.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        
        let aspectRatio: CGFloat = 16.0 / 9.0 // Hardcoded for now.
        
        let width = self.screenshotsCollectionView.bounds.width - (layout.minimumInteritemSpacing * 2)
        
        let itemWidth = width / 1.5
        let itemHeight = itemWidth * aspectRatio
        
        return CGSize(width: itemWidth, height: itemHeight)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.contentInset.bottom = 20
                
        self.screenshotsCollectionView.dataSource = self.screenshotsDataSource
        self.screenshotsCollectionView.prefetchDataSource = self.screenshotsDataSource
        
        self.subtitleLabel.text = self.app.subtitle
        self.descriptionTextView.text = self.app.localizedDescription
        
        if let version = self.app.latestAvailableVersion
        {
            self.versionDescriptionTextView.text = version.localizedDescription
            self.versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), version.version)
            self.versionDateLabel.text = Date().relativeDateString(since: version.date, dateFormatter: self.dateFormatter)
            self.sizeLabel.text = self.byteCountFormatter.string(fromByteCount: version.size)
        }
        else
        {
            self.versionDescriptionTextView.text = nil
            self.versionLabel.text = nil
            self.versionDateLabel.text = nil
            self.sizeLabel.text = self.byteCountFormatter.string(fromByteCount: 0)
        }
        
        self.descriptionTextView.maximumNumberOfLines = 5
        self.descriptionTextView.moreButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)
        
        self.versionDescriptionTextView.maximumNumberOfLines = 3
        self.versionDescriptionTextView.moreButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        guard var size = self.preferredScreenshotSize else { return }
        size.height = min(size.height, self.screenshotsCollectionView.bounds.height) // Silence temporary "item too tall" warning.
        
        let layout = self.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = size
        
        let permissionsHeight = self.appDetailCollectionViewController.collectionView.contentSize.height
        if self.appDetailCollectionViewHeightConstraint.constant != permissionsHeight && permissionsHeight > 10
        {
            self.appDetailCollectionViewHeightConstraint.constant = permissionsHeight
        }
    }
}

private extension AppContentViewController
{
    func makeScreenshotsDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>(items: self.app.screenshotURLs as [NSURL])
        dataSource.cellConfigurationHandler = { (cell, screenshot, indexPath) in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { (imageURL, indexPath, completionHandler) in
            return RSTAsyncBlockOperation() { (operation) in
                let request = ImageRequest(url: imageURL as URL, processors: [.screenshot])
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
    
    @IBSegueAction
    func makeAppDetailCollectionViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        let appDetailViewController = AppDetailCollectionViewController(app: self.app, coder: coder)
        self.appDetailCollectionViewController = appDetailViewController
        return appDetailViewController
    }
}

private extension AppContentViewController
{
    @objc func toggleCollapsingSection(_ sender: UIButton)
    {
        let indexPath: IndexPath
        
        switch sender
        {
        case self.descriptionTextView.moreButton: indexPath = IndexPath(row: Row.description.rawValue, section: 0)
        case self.versionDescriptionTextView.moreButton: indexPath = IndexPath(row: Row.versionDescription.rawValue, section: 0)
        default: return
        }
        
        // Disable animations to prevent some potentially strange ones.
        UIView.performWithoutAnimation {
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}

extension AppContentViewController
{
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
    {
        cell.tintColor = self.app.tintColor
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        switch Row.allCases[indexPath.row]
        {
        case .screenshots:
            guard let size = self.preferredScreenshotSize else { return 0.0 }
            return size.height
            
        case .permissions:
            guard !self.app.permissions.isEmpty else { return 0.0 }
            return UITableView.automaticDimension
            
        default:
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
    }
}

extension AppContentViewController: UIPopoverPresentationControllerDelegate
{
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
    {
        return .none
    }
}
