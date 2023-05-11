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
}

private let sectionInset = 20.0

class AppDetailCollectionViewController: UICollectionViewController
{
    let app: StoreApp
    private let privacyPermissions: [AppPermission]
    private let backgroundPermissions: [AppPermission]
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
        self.privacyPermissions = app.permissions.filter { $0.type == .privacy }.sorted(by: { $0.localizedName < $1.localizedName })
        self.entitlementPermissions = app.permissions.filter { $0.type == .entitlement }.sorted(by: { $0.localizedName < $1.localizedName })
        self.backgroundPermissions = app.permissions.filter { $0.type == .backgroundMode }.sorted(by: { $0.localizedName < $1.localizedName })
        
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.panGestureRecognizer.isEnabled = false
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "PrivacyCell")
        self.collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        // Header Registration
        self.headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { (headerView, elementKind, indexPath) in
            var configuration = headerView.defaultContentConfiguration()
            configuration.text = NSLocalizedString("Entitlements", comment: "")
            
//            configuration.textProperties.font = .boldSystemFont(ofSize: 16)
            
            headerView.contentConfiguration = configuration
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
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.interSectionSpacing = 10
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let section = Section(rawValue: sectionIndex) else { return nil }
            switch section
            {
            case .privacy:
                guard !self.privacyPermissions.isEmpty else { return nil }
                
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(50)) // Underestimate height to prevent jumping size abruptly.
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
//                let groupWidth = layoutEnvironment.container.contentSize.width - sectionInset * 2
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(50))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
//                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sectionInset, bottom: 4, trailing: sectionInset)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
//                layoutSection.boundarySupplementaryItems = [sectionFooter]
                return layoutSection
                
            case .entitlements:
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.headerMode = .supplementary
                
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
    
    func makePrivacyDataSource() -> RSTCompositeCollectionViewDataSource<AppPermission>
    {
        let privacyDataSource = RSTDynamicCollectionViewDataSource<AppPermission>()
        privacyDataSource.numberOfSectionsHandler = { 1 }
        privacyDataSource.cellConfigurationHandler = { [weak self] (cell, _, indexPath) in
            guard let self, #available(iOS 16, *) else { return }
            
            cell.contentConfiguration = UIHostingConfiguration {
                AppPermissionsCard(title: "Privacy",
                                   description: "\(self.app.name) may request access to the following:",
                                   tintColor: Color(uiColor: self.app.tintColor ?? .altPrimary),
                                   permissions: self.privacyPermissions)
            }
            .margins(.horizontal, 20)
        }
        
        let backgroundModesDataSource = RSTDynamicCollectionViewDataSource<AppPermission>()
        backgroundModesDataSource.numberOfSectionsHandler = { 1 }
        backgroundModesDataSource.cellConfigurationHandler = { [weak self] (cell, _, indexPath) in
            guard let self, #available(iOS 16, *) else { return }
            
            cell.contentConfiguration = UIHostingConfiguration {
                AppPermissionsCard(title: "Background Modes",
                                   description: "\(self.app.name) may perform the following tasks in the background:",
                                   tintColor: Color(uiColor: self.app.tintColor ?? .altPrimary),
                                   permissions: self.backgroundPermissions)
            }
            .margins(.horizontal, 20)
        }
        
        if #available(iOS 16, *)
        {
            privacyDataSource.numberOfItemsHandler = { [weak self] _ in self?.privacyPermissions.isEmpty == false ? 1 : 0 }
            backgroundModesDataSource.numberOfItemsHandler = { [weak self] _ in self?.backgroundPermissions.isEmpty == false ? 1 : 0 }
        }
        else
        {
            privacyDataSource.numberOfItemsHandler = { _ in 0 }
            backgroundModesDataSource.numberOfItemsHandler = { _ in 0 }
        }
        
        
        let dataSource = RSTCompositeCollectionViewDataSource(dataSources: [privacyDataSource, backgroundModesDataSource])
        dataSource.shouldFlattenSections = true
        dataSource.cellIdentifierHandler = { _ in "PrivacyCell" }
        return dataSource
    }

    func makeEntitlementsDataSource() -> RSTArrayCollectionViewDataSource<AppPermission>
    {
        let dataSource = RSTArrayCollectionViewDataSource(items: self.entitlementPermissions)
        dataSource.cellConfigurationHandler = { [weak self] (cell, appPermission, indexPath) in
            let cell = cell as! UICollectionViewListCell
            
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: appPermission.permission.sfIconName ?? "lock")
            content.imageProperties.tintColor = self?.app.tintColor ?? .altPrimary
            
            if let name = appPermission.permission.localizedName
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

//private extension AppDetailCollectionViewController
//{
//    struct View: UIViewControllerRepresentable
//    {
//        func makeUIViewController(context: Context) -> AppDetailCollectionViewController
//        {
//            let appDetailViewController = AppDetailCollectionViewController()
//            return appDetailViewController
//        }
//
//        func updateUIViewController(_ uiViewController: AppDetailCollectionViewController, context: Context)
//        {
//        }
//    }
//}

//@available(iOS 16, *)
//struct AppDetailCollectionViewController_Previews: PreviewProvider {
//    static var previews: some View {
//
//        AppDetailCollectionViewController.View()
//
////        let permissions: [ALTAppPrivacyPermission] = [
////            .camera,
////            .faceID,
////            .appleMusic,
////            .bluetooth,
////            .calendars,
////            .photos
////        ].sorted(by: { ($0.localizedName ?? $0.rawValue) < ($1.localizedName ?? $1.rawValue) })
////
////        AppPermissionsCard(title: Text("Privacy"),
////                           description: Text("Delta may request access to the following:"),
////                           permissions: permissions)
////            .frame(width: 350)
////            .previewLayout(.sizeThatFits)
//    }
//}
