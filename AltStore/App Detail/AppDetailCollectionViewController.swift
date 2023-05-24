//
//  AppDetailCollectionViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/5/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltStoreCore
import Roxas

extension AppDetailCollectionViewController
{
    private enum Section: Int
    {
        case privacy
        case entitlements
    }
    
    private enum ElementKind: String
    {
        case title
        case button
    }
    
    @objc(SafeAreaIgnoringCollectionView)
    private class SafeAreaIgnoringCollectionView: UICollectionView
    {
        override var safeAreaInsets: UIEdgeInsets {
            get {
                // Fixes incorrect layout if collection view height is taller than safe area height.
                return .zero
            }
            set {
                // There MUST be a setter for this to work, even if it does nothing ¯\_(ツ)_/¯
            }
        }
    }
}

class AppDetailCollectionViewController: UICollectionViewController
{
    let app: StoreApp
    private let privacyPermissions: [AppPermission]
    private let entitlementPermissions: [AppPermission]
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var privacyDataSource = self.makePrivacyDataSource()
    private lazy var entitlementsDataSource = self.makeEntitlementsDataSource()
    
    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    
    override var collectionViewLayout: UICollectionViewCompositionalLayout {
        return self.collectionView.collectionViewLayout as! UICollectionViewCompositionalLayout
    }
    
    init?(app: StoreApp, coder: NSCoder)
    {
        self.app = app
        
        let comparator: (AppPermission, AppPermission) -> Bool = { (permissionA, permissionB) -> Bool in
            switch (permissionA.localizedName, permissionB.localizedName)
            {
            case (let nameA?, let nameB?):
                // Sort by localizedName, if both have one.
                return nameA.localizedStandardCompare(nameB) == .orderedAscending
                
            case (nil, nil):
                // Sort by raw permission value as fallback.
                return permissionA.permission.rawValue < permissionB.permission.rawValue
                
            // Sort "known" permissions before "unknown" ones.
            case (_?, nil): return true
            case (nil, _?): return false
            }
        }
        
        self.privacyPermissions = app.permissions.filter { $0.type == .privacy }.sorted(by: comparator)
        self.entitlementPermissions = app.permissions.filter { $0.type == .entitlement }.sorted(by: comparator)
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Allow parent background color to show through.
        self.collectionView.backgroundColor = nil
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "PrivacyCell")
        self.collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { (headerView, elementKind, indexPath) in
            var configuration = UIListContentConfiguration.plainHeader()
            configuration.text = NSLocalizedString("Entitlements", comment: "")
            configuration.directionalLayoutMargins.bottom = 15
            
            headerView.contentConfiguration = configuration
            headerView.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        self.collectionView.delegate = self
    }
}

private extension AppDetailCollectionViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [privacyPermissions, entitlementPermissions] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
            switch section
            {
            case .privacy:
                guard !privacyPermissions.isEmpty, #available(iOS 16, *) else { return nil } // Hide section pre-iOS 16.
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(50)) // Underestimate height to prevent jumping size abruptly.
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(50))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                return layoutSection
                
            case .entitlements:
                guard !entitlementPermissions.isEmpty else { return nil }
                
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.headerMode = .supplementary
                configuration.backgroundColor = .altBackground
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
            }
        })
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<AppPermission>
    {
        let dataSource = RSTCompositeCollectionViewDataSource(dataSources: [self.privacyDataSource, self.entitlementsDataSource])
        return dataSource
    }
    
    func makePrivacyDataSource() -> RSTDynamicCollectionViewDataSource<AppPermission>
    {
        let dataSource = RSTDynamicCollectionViewDataSource<AppPermission>()
        dataSource.cellIdentifierHandler = { _ in "PrivacyCell" }
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.cellConfigurationHandler = { [weak self] (cell, _, indexPath) in
            guard let self, #available(iOS 16, *) else { return }
            
            cell.contentConfiguration = UIHostingConfiguration {
                AppPermissionsCard(title: "Privacy",
                                   description: "\(self.app.name) may request access to the following:",
                                   tintColor: Color(uiColor: self.app.tintColor ?? .altPrimary),
                                   permissions: self.privacyPermissions)
            }
            .margins(.horizontal, 20)
        }
        
        if #available(iOS 16, *)
        {
            dataSource.numberOfItemsHandler = { [privacyPermissions] _ in !privacyPermissions.isEmpty ? 1 : 0 }
        }
        else
        {
            dataSource.numberOfItemsHandler = { _ in 0 }
        }
        
        return dataSource
    }

    func makeEntitlementsDataSource() -> RSTArrayCollectionViewDataSource<AppPermission>
    {
        let dataSource = RSTArrayCollectionViewDataSource(items: self.entitlementPermissions)
        dataSource.cellConfigurationHandler = { [weak self] (cell, appPermission, indexPath) in
            let cell = cell as! UICollectionViewListCell
            
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: appPermission.effectiveSymbolName)
            
            let tintColor = self?.app.tintColor ?? .altPrimary
            content.imageProperties.tintColor = tintColor
            
            if let name = appPermission.localizedName
            {
                content.text = name
                content.secondaryText = appPermission.permission.rawValue
                content.secondaryTextProperties.color = UIColor.secondaryLabel
            }
            else
            {
                content.text = appPermission.permission.rawValue
            }
            
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            
            if #available(iOS 15.4, *) /*, let self */ // Capturing self leads to strong-reference cycle.
            {
                let detailAccessory = UICellAccessory.detail(displayed: .always, options: .init(tintColor: tintColor)) {
                    let alertController = UIAlertController(title: appPermission.localizedDisplayName, message: appPermission.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(.ok)
                    self?.present(alertController, animated: true)
                }
                
                cell.accessories = [detailAccessory]
            }
        }

        return dataSource
    }
}

extension AppDetailCollectionViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = self.collectionView.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: indexPath)
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool
    {
        return false
    }
    
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool
    {
        return false
    }
}
