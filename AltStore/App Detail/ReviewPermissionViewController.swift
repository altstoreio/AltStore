//
//  ReviewPermissionViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

class Box<T>: NSObject
{
    let value: T
    
    init(_ value: T)
    {
        self.value = value
    }
}

class PermissionCell: UICollectionViewListCell
{
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let layoutAttributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        
        if layoutAttributes.size.height < 51
        {
            layoutAttributes.size.height = 51
        }
        
        return layoutAttributes
    }
}

extension ReviewPermissionsViewController
{
    private enum Section: Int, CaseIterable
    {
        case description
        case permissions
        case allowButton
    }
}

class ReviewPermissionsViewController: UICollectionViewController
{
    let app: AppProtocol
    let permissions: [any ALTAppPermission]
    
    let permissionsMode: VerifyAppOperation.PermissionsMode
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var emptyDataSource = self.makeEmptyDataSource()
    private lazy var permissionsDataSource = self.makePermissionsDataSource()
    private lazy var confirmButtonDataSource = self.makeConfirmButtonDataSource()
    
    var resultHandler: ((Bool) -> Void)?
    
    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    
    init(app: AppProtocol, permissions: [any ALTAppPermission], mode: VerifyAppOperation.PermissionsMode)
    {
        self.app = app
        self.permissions = permissions.sorted { $0.localizedDisplayName.localizedCompare($1.localizedDisplayName) == .orderedAscending }
        self.permissionsMode = mode
                
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = UIColor(named: "SettingsBackground")
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
            switch section
            {
            case .description: listConfiguration.headerMode = .supplementary
            case .permissions, .allowButton: listConfiguration.headerMode = .none
            }
            
            let layoutSection = NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: layoutEnvironment)
            return layoutSection
        })
        
        super.init(collectionViewLayout: layout)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
                
        
        let buttonAppearance = UIBarButtonItemAppearance(style: .plain)
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.buttonAppearance = buttonAppearance
        
        self.navigationItem.standardAppearance = appearance
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.register(PermissionCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")
        
        self.headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { (headerView, elementKind, indexPath) in
            var configuration = headerView.defaultContentConfiguration()
            configuration.secondaryText = NSLocalizedString("The permissions for AltStore have changed since last installation.", comment: "")
            headerView.contentConfiguration = configuration
        }
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ReviewPermissionsViewController.cancelReviewingPermissions))
        self.navigationItem.leftBarButtonItem = cancelButton
    }
}

private extension ReviewPermissionsViewController
{
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTCompositeCollectionViewDataSource(dataSources: [self.emptyDataSource, self.permissionsDataSource, self.confirmButtonDataSource])
        return dataSource
    }
    
    func makeEmptyDataSource() -> RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 0 }
        return dataSource
    }
    
    func makePermissionsDataSource() -> RSTArrayCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTArrayCollectionViewDataSource(items: self.permissions.map { Box($0) })
        dataSource.cellConfigurationHandler = { [weak self] (cell, box, indexPath) in
            let cell = cell as! UICollectionViewListCell
            let permission = box.value
            
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: permission.sfIconName ?? "lock")
            content.imageProperties.tintColor = .white
//            content.imageProperties.tintColor = self?.app.tintColor ?? .altPrimary
            
            content.text = permission.localizedName ?? permission.rawValue
            content.textProperties.color = .white
            content.textProperties.font = UIFont.boldSystemFont(ofSize: 17)
            
            content.secondaryText = permission.localizedExplanation
            content.secondaryTextProperties.color = .white.withAlphaComponent(0.8)
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 17)
            
            cell.contentConfiguration = content
            
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.cornerRadius = 16
            background.backgroundColor = .white.withAlphaComponent(0.25)
            cell.backgroundConfiguration = background
        }
        
        return dataSource
    }
    
    func makeConfirmButtonDataSource() -> RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 1 }
        dataSource.cellConfigurationHandler = { (cell, _, indexPath) in
            let cell = cell as! UICollectionViewListCell
            
            var content = cell.defaultContentConfiguration()
            content.textProperties.alignment = .center
            content.textProperties.color = .white
            content.textProperties.font = UIFont.boldSystemFont(ofSize: 17)
            
            content.text = NSLocalizedString("Confirm", comment: "")
            
            cell.contentConfiguration = content
            
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = UIColor(named: "SettingsHighlighted")
            background.cornerRadius = 16
            cell.backgroundConfiguration = background
        }
        
        return dataSource
    }
}

private extension ReviewPermissionsViewController
{
    @objc func cancelReviewingPermissions()
    {
        self.resultHandler?(false)
        
        self.dismiss(animated: true)
    }
}

extension ReviewPermissionsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
//        let headerView = self.collectionView.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: indexPath)
        
        let headerView = self.collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header", for: indexPath) as! UICollectionViewListCell
        
        var configuration =  UIListContentConfiguration.sidebarCell()
        
        switch self.permissionsMode
        {
        case .none: break
        case .added: configuration.text = String(format: NSLocalizedString("The permissions for %@ have changed since last installation. Please review them below.", comment: ""), self.app.name)
        case .all: configuration.text = String(format: NSLocalizedString("%@ will be automatically given these permissions once installed. Please review them below.", comment: ""), self.app.name)
        }
        
        
        configuration.textProperties.color = .white.withAlphaComponent(0.8)
        configuration.textProperties.numberOfLines = 0
        headerView.contentConfiguration = configuration
        
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        guard let section = Section(rawValue: indexPath.section), section == .allowButton else { return }
        
        self.resultHandler?(true)
        
        self.dismiss(animated: true)
    }
}
