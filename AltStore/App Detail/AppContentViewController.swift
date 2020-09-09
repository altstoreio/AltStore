//
//  AppContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
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
    private lazy var permissionsDataSource = self.makePermissionsDataSource()
    
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
    @IBOutlet private var permissionsCollectionView: UICollectionView!
    
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
        
        self.permissionsCollectionView.dataSource = self.permissionsDataSource
        
        self.subtitleLabel.text = self.app.subtitle
        self.descriptionTextView.text = self.app.localizedDescription
        self.versionDescriptionTextView.text = self.app.versionDescription
        self.versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), self.app.version)
        self.versionDateLabel.text = Date().relativeDateString(since: self.app.versionDate, dateFormatter: self.dateFormatter)
        self.sizeLabel.text = self.byteCountFormatter.string(fromByteCount: Int64(self.app.size))
        
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
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "showPermission" else { return }
        
        guard let cell = sender as? UICollectionViewCell, let indexPath = self.permissionsCollectionView.indexPath(for: cell) else { return }
        
        let permission = self.permissionsDataSource.item(at: indexPath)
        
        let maximumWidth = self.view.bounds.width - 20
        
        let permissionPopoverViewController = segue.destination as! PermissionPopoverViewController
        permissionPopoverViewController.permission = permission
        permissionPopoverViewController.view.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
        
        let size = permissionPopoverViewController.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        permissionPopoverViewController.preferredContentSize = size
        
        permissionPopoverViewController.popoverPresentationController?.delegate = self
        permissionPopoverViewController.popoverPresentationController?.sourceRect = cell.frame
        permissionPopoverViewController.popoverPresentationController?.sourceView = self.permissionsCollectionView
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
    
    func makePermissionsDataSource() -> RSTArrayCollectionViewDataSource<AppPermission>
    {        
        let dataSource = RSTArrayCollectionViewDataSource(items: self.app.permissions)
        dataSource.cellConfigurationHandler = { (cell, permission, indexPath) in
            let cell = cell as! PermissionCollectionViewCell
            cell.button.setImage(permission.type.icon, for: .normal)
            cell.textLabel.text = permission.type.localizedShortName
        }
        
        return dataSource
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
        guard indexPath.row == Row.screenshots.rawValue else { return super.tableView(tableView, heightForRowAt: indexPath) }
        
        guard let size = self.preferredScreenshotSize else { return 0.0 }
        return size.height
    }
}

extension AppContentViewController: UIPopoverPresentationControllerDelegate
{
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
    {
        return .none
    }
}
