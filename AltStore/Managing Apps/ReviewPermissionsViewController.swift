//
//  ReviewPermissionsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 11/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltSign
import AltStoreCore
import Roxas

//private extension Color
//{
//    static let altGradientLight = Color.init(.displayP3, red: 123.0/255.0, green: 200.0/255.0, blue: 176.0/255.0)
//    static let altGradientDark = Color.init(.displayP3, red: 0.0/255.0, green: 128.0/255.0, blue: 132.0/255.0)
//    
//    static let altGradientExtraDark = Color.init(.displayP3, red: 2.0/255.0, green: 82.0/255.0, blue: 103.0/255.0)
//}

class Box<T>
{
    var value: T
    
    init(_ value: T)
    {
        self.value = value
    }
}

@available(iOS 16, *)
extension ReviewPermissionsViewController
{
    private enum Section: Int
    {
//        case knownHeader
        case known
//        case unknownHeader
        case unknown
        
        case approve
    }
}

@available(iOS 16, *)
class ReviewPermissionsViewController: UICollectionViewController
{
    var app: AppProtocol!
    
    var permissions: [any ALTAppPermission] = [] {
        didSet {
            let permissions = self.permissions.sorted {
                $0.localizedDisplayName.localizedStandardCompare($1.localizedDisplayName) == .orderedAscending
            }.map(Box.init)
            
            let knownPermissions = permissions.filter { $0.value.isKnown }
            let unknownPermissions = permissions.filter { !$0.value.isKnown }
            
            self.knownPermissionsDataSource.items = knownPermissions
            self.unknownPermissionsDataSource.items = unknownPermissions
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var knownPermissionsDataSource = self.makeKnownPermissionsDataSource()
    private lazy var unknownPermissionsDataSource = self.makeUnknownPermissionsDataSource()
    
    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            let appearance = navigationBar.standardAppearance
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(resource: .gradientTop)
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
            navigationBar.standardAppearance = appearance
        }
        
        self.title = NSLocalizedString("Review Permissions", comment: "")
        
        let collectionViewLayout = self.makeLayout()
        collectionViewLayout.register(VibrantBackgroundView.self, forDecorationViewOfKind: "Background")
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        //guard #available(iOS 16, *) else { return }
        
        self.collectionView.backgroundView = UIHostingConfiguration {
            LinearGradient(colors: [Color(.gradientTop), Color(.gradientBottom)], startPoint: .top, endPoint: .bottom)
        }
        .margins(.all, 0)
        .makeContentView()
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        
        self.collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        
        let cancelButton = UIBarButtonItem(systemItem: .cancel)
        self.navigationItem.leftBarButtonItem = cancelButton
        
        self.prepareCollectionView()
    }
    
    func prepareCollectionView()
    {
        self.headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { (headerView, elementKind, indexPath) in
            var configuration = UIListContentConfiguration.prominentInsetGroupedHeader()
            configuration.textProperties.color = .white
            configuration.secondaryTextProperties.color = .white.withAlphaComponent(0.8)
            configuration.textToSecondaryTextVerticalPadding = 8
                        
            switch Section(rawValue: indexPath.section)!
            {
            case .known:
                configuration.text = nil
                configuration.secondaryText = String(format: NSLocalizedString("%@ will be automatically given these permissions once installed.", comment: ""), self.app.name)
                
            case .unknown:
                configuration.text = NSLocalizedString("Additional Permissions", comment: "")
                configuration.secondaryText = String(format: NSLocalizedString("These are permissions required by %@ that AltStore does not recognize. Make sure you understand them before continuing.", comment: ""), self.app.name)
                
            case .approve: break
                
//            case .known, .unknown: break
            }
                        
            headerView.contentConfiguration = configuration
            headerView.backgroundConfiguration = UIBackgroundConfiguration.clear()
        }
    }
}

@available(iOS 16, *)
extension ReviewPermissionsViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        //config.interSectionSpacing = 44
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self, let section = Section(rawValue: sectionIndex) else { return nil }
            
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = true
            configuration.separatorConfiguration.color = UIColor(resource: .gradientBottom).withAlphaComponent(0.7) //.white.withAlphaComponent(0.8)
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 20
            configuration.backgroundColor = .clear
            
            switch section
            {
            case .known: configuration.headerMode = self.knownPermissionsDataSource.items.isEmpty ? .none : .supplementary
            case .unknown: configuration.headerMode = self.unknownPermissionsDataSource.items.isEmpty ? .none : .supplementary
            case .approve: configuration.headerMode = .none
            }
            
            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            
//            switch section
//            {
//            case .knownHeader: break
//            case .unknownHeader: break
//            case .known, .unknown:
//                let backgroundItem = NSCollectionLayoutDecorationItem.background(elementKind: "Background")
////                layoutSection.decorationItems = [backgroundItem]
//            }
            
            layoutSection.contentInsets.top = 15
            
            switch section
            {
            case .known, .approve: layoutSection.contentInsets.bottom = 44
            case .unknown: layoutSection.contentInsets.bottom = 20
            }

            return layoutSection
        }, configuration: config)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let knownHeaderDataSource = RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>()
        knownHeaderDataSource.numberOfSectionsHandler = { 1 }
        knownHeaderDataSource.numberOfItemsHandler = { _ in 0 }
        
        let unknownHeaderDataSource = RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>()
        unknownHeaderDataSource.numberOfSectionsHandler = { 1 }
        unknownHeaderDataSource.numberOfItemsHandler = { _ in 0 }
        
        let approveDataSource = RSTDynamicCollectionViewDataSource<Box<any ALTAppPermission>>()
        approveDataSource.numberOfSectionsHandler = { 1 }
        approveDataSource.numberOfItemsHandler = { _ in 1 }
        approveDataSource.cellConfigurationHandler = { cell, _, indexPath in
            let cell = cell as! UICollectionViewListCell
            
            var config = cell.defaultContentConfiguration()
            config.text = NSLocalizedString("Approve", comment: "")
            config.textProperties.color = .white
            config.textProperties.font = UIFont.preferredFont(forTextStyle: .headline)
            config.textProperties.alignment = .center
            config.directionalLayoutMargins.top = 15
            config.directionalLayoutMargins.bottom = 15
            
            cell.configurationUpdateHandler = { cell, state in
                var content = config.updated(for: state)
                
                if state.isHighlighted
                {
                    content.textProperties.color = .white.withAlphaComponent(0.5)
                }
                
                cell.contentConfiguration = content
            }
            
            cell.contentConfiguration = config
            
            var backgroundConfig = UIBackgroundConfiguration.listGroupedCell()
            backgroundConfig.backgroundColor = UIColor(resource: .darkButtonBackground)
            backgroundConfig.visualEffect = nil
            cell.backgroundConfiguration = backgroundConfig
        }
        
        let dataSource = RSTCompositeCollectionViewDataSource(dataSources: [self.knownPermissionsDataSource,
                                                                            self.unknownPermissionsDataSource,
                                                                            approveDataSource])
        return dataSource
    }
    
    func makeKnownPermissionsDataSource() -> RSTArrayCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTArrayCollectionViewDataSource<Box<any ALTAppPermission>>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, permission, indexPath in
            let cell = cell as! UICollectionViewListCell
            self?.configure(cell, permission: permission)
        }
        
        return dataSource
    }
    
    func makeUnknownPermissionsDataSource() -> RSTArrayCollectionViewDataSource<Box<any ALTAppPermission>>
    {
        let dataSource = RSTArrayCollectionViewDataSource<Box<any ALTAppPermission>>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, permission, indexPath in
            let cell = cell as! UICollectionViewListCell
            self?.configure(cell, permission: permission)
        }
        
        return dataSource
    }
    
    func configure(_ cell: UICollectionViewListCell, permission: Box<any ALTAppPermission>) // Use some ALTAppPermission?
    {
        var config = cell.defaultContentConfiguration()
        config.text = permission.value.localizedDisplayName
        config.textProperties.font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).bolded(), size: 0.0)
        config.textProperties.color = .label
        config.textToSecondaryTextVerticalPadding = 5.0
        config.directionalLayoutMargins.top = 20
        config.directionalLayoutMargins.bottom = 20
        
        config.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .subheadline)
        config.secondaryTextProperties.color = .white.withAlphaComponent(0.8)
        
        config.imageProperties.tintColor = .white
        config.imageToTextPadding = 20
        config.directionalLayoutMargins.leading = 20
//            config.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)
        
        if permission.value.isKnown
        {
            let symbolConfig = UIImage.SymbolConfiguration(scale: .large)
            config.image = UIImage(systemName: permission.value.effectiveSymbolName)
            config.secondaryText = permission.value.localizedDescription
        }
        else
        {
            config.image = nil
            config.secondaryText = permission.value.rawValue
        }
        
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .white.withAlphaComponent(0.25)
        backgroundConfiguration.visualEffect = UIVibrancyEffect(blurEffect: .init(style: .systemMaterial), style: .fill)
        cell.backgroundConfiguration = backgroundConfiguration
        
//            cell.backgroundConfiguration?.backgroundColor = .yellow.withAlphaComponent(0.3)
        
        cell.contentConfiguration = config
        
        cell.overrideUserInterfaceStyle = .dark
    }
}

@available(iOS 16, *)
extension ReviewPermissionsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = self.collectionView.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: indexPath)
        return headerView
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
   
//    let storyboard = UIStoryboard(name: "Main", bundle: .main)
//    let browseViewController = storyboard.instantiateViewController(identifier: "browseViewController") { coder in
//        BrowseViewController(source: nil, coder: coder)
//    }
    
    let reviewPermissionsViewController = ReviewPermissionsViewController(collectionViewLayout: UICollectionViewFlowLayout())
    reviewPermissionsViewController.app = AnyApp(name: "Delta", bundleIdentifier: "com.rileytestut.Delta", url: nil, storeApp: nil)
    reviewPermissionsViewController.permissions = [
        ALTEntitlement.getTaskAllow,
        ALTEntitlement.appGroups,
        ALTEntitlement.interAppAudio,
        ALTEntitlement.keychainAccessGroups,
        ALTEntitlement("com.apple.developer.virtual-addressing"),
        ALTEntitlement("com.apple.developer.increased-memory-limit")
    ]
    
    let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
    return navigationController
}
