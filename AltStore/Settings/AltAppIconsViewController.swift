//
//  AltAppIconsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 2/14/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltSign
import AltStoreCore
import Roxas

extension UIApplication
{
    static let didChangeAppIconNotification = Notification.Name("io.altstore.AppManager.didChangeAppIcon")
}

private final class AltIcon: Decodable
{
    static let defaultIconName: String = "AppIcon"
    
    var name: String
    var imageName: String
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case imageName
    }
    
    required init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.imageName = try container.decode(String.self, forKey: .imageName)
    }
}

extension AltAppIconsViewController
{
    private enum Section: String, CaseIterable, Decodable, CodingKeyRepresentable
    {
        case modern
        case gradient
        case recessed
        case classic
        
        var localizedName: String {
            switch self
            {
            case .modern: return NSLocalizedString("Modern", comment: "")
            case .gradient: return NSLocalizedString("Gradient", comment: "")
            case .recessed: return NSLocalizedString("Recessed", comment: "")
            case .classic: return NSLocalizedString("Classic", comment: "")
            }
        }
    }
}

class AltAppIconsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private var iconsBySection = [Section: [AltIcon]]()
    
    private var headerRegistration: UICollectionView.SupplementaryRegistration<UICollectionViewListCell>!
        
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("Change App Icon", comment: "")
        
        let collectionViewLayout = self.makeLayout()
        self.collectionView.collectionViewLayout = collectionViewLayout
        
        self.collectionView.backgroundColor = UIColor(resource: .settingsBackground)
        
        do
        {
            let fileURL = Bundle.main.url(forResource: "AltIcons", withExtension: "plist")!
            let data = try Data(contentsOf: fileURL)
            
            let icons = try PropertyListDecoder().decode([Section: [AltIcon]].self, from: data)
            self.iconsBySection = icons
        }
        catch
        {
            Logger.main.error("Failed to load alternate icons. \(error.localizedDescription, privacy: .public)")
        }
        
        self.dataSource.proxy = self
        self.collectionView.dataSource = self.dataSource
        
        self.collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
                
        self.headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { (headerView, elementKind, indexPath) in
            let section = Section.allCases[indexPath.section]
            
            let font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).bolded(), size: 0.0)
            
            var configuration = UIListContentConfiguration.cell()
            configuration.text = section.localizedName
            configuration.textProperties.font = font
            configuration.textProperties.color = .white.withAlphaComponent(0.8)
            headerView.contentConfiguration = configuration
            
            headerView.backgroundConfiguration = .clear()
        }
    }
}

private extension AltAppIconsViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.showsSeparators = true
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
                
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<AltIcon>
    {
        let dataSources = Section.allCases.compactMap { self.iconsBySection[$0] }.filter { !$0.isEmpty }.map { icons in
            let dataSource = RSTArrayCollectionViewDataSource(items: icons)
            return dataSource
        }
        
        let dataSource = RSTCompositeCollectionViewDataSource(dataSources: dataSources)
        dataSource.cellConfigurationHandler = { cell, icon, indexPath in
            let cell = cell as! UICollectionViewListCell
            
            let imageWidth = 44.0
            let font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).bolded(), size: 0.0)
            
            var config = cell.defaultContentConfiguration()
            config.text = icon.name
            config.textProperties.font = font
            config.textProperties.color = .label
            
            let image = UIImage(named: icon.imageName)
            config.image = image
            config.imageProperties.maximumSize = CGSize(width: imageWidth, height: imageWidth)
            config.imageProperties.cornerRadius = imageWidth / 5.0 // Copied from AppIconImageView
            
            cell.contentConfiguration = config

            if UIApplication.shared.alternateIconName == icon.imageName || (UIApplication.shared.alternateIconName == nil && icon.imageName == AltIcon.defaultIconName)
            {
                cell.accessories = [.checkmark(options: .init(tintColor: .white))]
            }
            else
            {
                cell.accessories = []
            }
                      
            var backgroundConfiguration = UIBackgroundConfiguration.listPlainCell()
            backgroundConfiguration.backgroundColorTransformer = UIConfigurationColorTransformer { [weak cell] c in
                if let state = cell?.configurationState, state.isHighlighted 
                {
                    // Highlighted, so use darker white for background.
                    return .white.withAlphaComponent(0.4)
                }
                
                return .white.withAlphaComponent(0.25)
            }
            cell.backgroundConfiguration = backgroundConfiguration
                        
            // Ensure text is legible on green background.
            cell.overrideUserInterfaceStyle = .dark
        }
        
        return dataSource
    }
}

extension AltAppIconsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let headerView = self.collectionView.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: indexPath)
        return headerView
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let icon = self.dataSource.item(at: indexPath)
        guard UIApplication.shared.alternateIconName != icon.imageName else { return }
        
        // Deselect previous icon + select new icon
        collectionView.reloadData()
        
        // If assigning primary icon, pass "nil" as alternate icon name.
        let imageName = (icon.imageName == "AppIcon") ? nil : icon.imageName
        UIApplication.shared.setAlternateIconName(imageName) { error in
            if let error
            {
                let alertController = UIAlertController(title: NSLocalizedString("Unable to Change App Icon", comment: ""),
                                                        message: error.localizedDescription,
                                                        preferredStyle: .alert)
                alertController.addAction(.ok)
                self.present(alertController, animated: true)
                
                collectionView.reloadData()
            }
            else
            {
                NotificationCenter.default.post(name: UIApplication.didChangeAppIconNotification, object: icon)
            }
        }
    }
}

@available(iOS 17, *)
#Preview(traits: .portrait) {
    let altAppIconsViewController = AltAppIconsViewController(collectionViewLayout: UICollectionViewFlowLayout())
    
    let navigationController = UINavigationController(rootViewController: altAppIconsViewController)
    return navigationController
}
