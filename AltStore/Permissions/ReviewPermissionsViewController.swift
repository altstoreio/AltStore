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

@available(iOS 15, *)
extension ReviewPermissionsViewController
{
    private enum Section: Int
    {
        case known
        case unknown
        case approve
    }
}

@available(iOS 15, *)
class ReviewPermissionsViewController: UICollectionViewController
{
    let app: AppProtocol
    let permissions: [ALTEntitlement]
    
    let permissionsMode: VerifyAppOperation.PermissionReviewMode
    
    var completionHandler: ((Result<Void, Error>) -> Void)?
    
    private let knownPermissions: [any ALTAppPermission]
    private let unknownPermissions: [any ALTAppPermission]
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var knownPermissionsDataSource = self.makeKnownPermissionsDataSource()
    private lazy var unknownPermissionsDataSource = self.makeUnknownPermissionsDataSource()
    
    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
    
    init(app: AppProtocol, permissions: [ALTEntitlement], mode: VerifyAppOperation.PermissionReviewMode)
    {
        self.app = app
        self.permissions = permissions
        self.permissionsMode = mode
        
        let sortedPermissions = permissions.sorted {
            $0.localizedDisplayName.localizedStandardCompare($1.localizedDisplayName) == .orderedAscending
        }
        
        let knownPermissions = sortedPermissions.filter { $0.isKnown }
        let unknownPermissions = sortedPermissions.filter { !$0.isKnown }
        
        self.knownPermissions = knownPermissions
        self.unknownPermissions = unknownPermissions
        
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
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
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(resource: .gradientTop)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.buttonAppearance = buttonAppearance
        self.navigationItem.standardAppearance = appearance
        
        self.title = NSLocalizedString("Review Permissions", comment: "")
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        if #available(iOS 16, *)
        {
            self.collectionView.backgroundView = UIHostingConfiguration {
                LinearGradient(colors: [Color(UIColor(resource: .gradientTop)), Color(.gradientBottom)], startPoint: .top, endPoint: .bottom)
            }
            .margins(.all, 0)
            .makeContentView()
        }
        else
        {
            self.collectionView.backgroundColor = UIColor(resource: .gradientBottom)
        }
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        
        self.collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ReviewPermissionsViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancelButton
        
        self.navigationController?.isModalInPresentation = true
        
        self.prepareCollectionView()
    }
}

@available(iOS 15, *)
extension ReviewPermissionsViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layout = UICollectionViewCompositionalLayout { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self, let section = Section(rawValue: sectionIndex) else { return nil }
            
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = true
            configuration.separatorConfiguration.color = UIColor(resource: .gradientBottom).withAlphaComponent(0.7)
            configuration.separatorConfiguration.bottomSeparatorInsets.leading = 20
            configuration.backgroundColor = .clear
            
            switch section
            {
            case .known: configuration.headerMode = .supplementary // Always show header even if no known permissions
            case .unknown: configuration.headerMode = self.unknownPermissionsDataSource.items.isEmpty ? .none : .supplementary
            case .approve: configuration.headerMode = .none
            }
            
            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            layoutSection.contentInsets.top = 15
            
            switch section
            {
            case .known:
                if self.knownPermissions.isEmpty
                {
                    layoutSection.contentInsets.top = 0
                    layoutSection.contentInsets.bottom = 20
                }
                else if self.unknownPermissions.isEmpty
                {
                    layoutSection.contentInsets.bottom = 20
                }
                else
                {
                    layoutSection.contentInsets.bottom = 44
                }
                
            case .unknown:
                if self.unknownPermissions.isEmpty
                {
                    layoutSection.contentInsets.top = 0
                    layoutSection.contentInsets.bottom = 0
                }
                else
                {
                    layoutSection.contentInsets.bottom = 20
                }
                
            case .approve: layoutSection.contentInsets.bottom = 44
            }
            
            return layoutSection
        }
        
        return layout
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
                
                switch self.permissionsMode
                {
                case .all: configuration.secondaryText = String(localized: "“\(self.app.name)” will be automatically given these permissions once installed.")
                case .added: configuration.secondaryText = String(localized: "This version of “\(self.app.name)” requires additional permissions.")
                case .none: break
                }
                
            case .unknown:
                configuration.text = NSLocalizedString("Additional Permissions", comment: "")
                configuration.secondaryText = String(format: NSLocalizedString("These are permissions required by “%@” that AltStore does not recognize. Make sure you understand them before continuing.", comment: ""), self.app.name)
                
            case .approve: break
            }
            
            headerView.contentConfiguration = configuration
            headerView.backgroundConfiguration = .clear()
        }
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<NSString>
    {
        let approveDataSource = RSTDynamicCollectionViewDataSource<NSString>()
        approveDataSource.numberOfSectionsHandler = { 1 }
        approveDataSource.numberOfItemsHandler = { _ in 1 }
        approveDataSource.cellConfigurationHandler = { cell, _, indexPath in
            let cell = cell as! UICollectionViewListCell
            
            var config = cell.defaultContentConfiguration()
            config.text = NSLocalizedString("Approve", comment: "")
            config.textProperties.color = .white
            config.textProperties.font = .preferredFont(forTextStyle: .headline)
            config.textProperties.alignment = .center
            config.directionalLayoutMargins.top = 15
            config.directionalLayoutMargins.bottom = 15
            cell.contentConfiguration = config
            
            cell.configurationUpdateHandler = { cell, state in
                var content = config.updated(for: state)
                
                // Change text color when highlighted
                if state.isHighlighted
                {
                    content.textProperties.color = .white.withAlphaComponent(0.5)
                }
                
                cell.contentConfiguration = content
            }
            
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
    
    func makeKnownPermissionsDataSource() -> RSTArrayCollectionViewDataSource<NSString>
    {
        let dataSource = RSTArrayCollectionViewDataSource<NSString>(items: self.knownPermissions.map { $0.rawValue as NSString })
        dataSource.cellConfigurationHandler = { [weak self] cell, permission, indexPath in
            let cell = cell as! UICollectionViewListCell
            let permission = ALTEntitlement(rawValue: permission as String)
            self?.configure(cell, permission: permission)
        }
        
        return dataSource
    }
    
    func makeUnknownPermissionsDataSource() -> RSTArrayCollectionViewDataSource<NSString>
    {
        let dataSource = RSTArrayCollectionViewDataSource<NSString>(items: self.unknownPermissions.map { $0.rawValue as NSString })
        dataSource.cellConfigurationHandler = { [weak self] cell, permission, indexPath in
            let cell = cell as! UICollectionViewListCell
            let permission = ALTEntitlement(rawValue: permission as String)
            self?.configure(cell, permission: permission)
        }
        
        return dataSource
    }
    
    func configure(_ cell: UICollectionViewListCell, permission: ALTEntitlement)
    {
        var config = cell.defaultContentConfiguration()
        config.text = permission.localizedDisplayName
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
        
        if permission.isKnown
        {
            let symbolConfig = UIImage.SymbolConfiguration(scale: .large)
            config.image = UIImage(systemName: permission.effectiveSymbolName, withConfiguration: symbolConfig)
            config.secondaryText = permission.localizedDescription
        }
        else
        {
            config.image = nil
            config.secondaryText = permission.rawValue
        }
        
        cell.contentConfiguration = config
        
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .white.withAlphaComponent(0.25)
        backgroundConfiguration.visualEffect = UIVibrancyEffect(blurEffect: .init(style: .systemMaterial), style: .fill)
        cell.backgroundConfiguration = backgroundConfiguration
        
        // Ensure text is legible on gradient background.
        cell.overrideUserInterfaceStyle = .dark
    }
}

@available(iOS 15, *)
private extension ReviewPermissionsViewController
{
    @objc
    func cancel()
    {
        self.completionHandler?(.failure(CancellationError()))
        self.completionHandler = nil
    }
}

@available(iOS 15, *)
extension ReviewPermissionsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = self.collectionView.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: indexPath)
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        guard let section = Section(rawValue: indexPath.section), section == .approve else { return }
        
        self.completionHandler?(.success(()))
        self.completionHandler = nil
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let app = AnyApp(name: "Delta", bundleIdentifier: "com.rileytestut.Delta", url: nil, storeApp: nil)
    let permissions: [ALTEntitlement] = [
        .getTaskAllow,
        .appGroups,
        .interAppAudio,
        .keychainAccessGroups,
        .init("com.apple.developer.extended-virtual-addressing"),
        .init("com.apple.developer.increased-memory-limit")
    ]
    
    let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: permissions, mode: .all)
    
    let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
    return navigationController
}
