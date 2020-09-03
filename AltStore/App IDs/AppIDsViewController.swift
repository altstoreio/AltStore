//
//  AppIDsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

class AppIDsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private var didInitialFetch = false
    private var isLoading = false {
        didSet {
            self.update()
        }
    }
    
    @IBOutlet var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.dataSource = self.dataSource
        
        self.activityIndicatorBarButtonItem.isIndicatingActivity = true
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(AppIDsViewController.fetchAppIDs), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if !self.didInitialFetch
        {
            self.fetchAppIDs()
        }
    }
}

private extension AppIDsViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewDataSource<AppID>
    {
        let fetchRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AppID.name, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.bundleIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.expirationDate, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        if let team = DatabaseManager.shared.activeTeam()
        {
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(AppID.team), team)
        }
        else
        {
            fetchRequest.predicate = NSPredicate(value: false)
        }
        
        let dataSource = RSTFetchedResultsCollectionViewDataSource<AppID>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { (cell, appID, indexPath) in
            let tintColor = UIColor.altPrimary
            
            let cell = cell as! BannerCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
                        
            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
            
            cell.bannerView.buttonLabel.text = NSLocalizedString("Expires in", comment: "")
            
            let attributedAccessibilityLabel = NSMutableAttributedString(string: appID.name + ". ")
            
            if let expirationDate = appID.expirationDate
            {
                cell.bannerView.button.isHidden = false
                cell.bannerView.button.isUserInteractionEnabled = false
                
                cell.bannerView.buttonLabel.isHidden = false
                
                let currentDate = Date()
                
                let numberOfDays = expirationDate.numberOfCalendarDays(since: currentDate)
                let numberOfDaysText = (numberOfDays == 1) ? NSLocalizedString("1 day", comment: "") : String(format: NSLocalizedString("%@ days", comment: ""), NSNumber(value: numberOfDays))
                cell.bannerView.button.setTitle(numberOfDaysText.uppercased(), for: .normal)
                
                attributedAccessibilityLabel.mutableString.append(String(format: NSLocalizedString("Expires in %@.", comment: ""), numberOfDaysText) + " ")
            }
            else
            {
                cell.bannerView.button.isHidden = true
                cell.bannerView.button.isUserInteractionEnabled = true
                
                cell.bannerView.buttonLabel.isHidden = true
            }
                                                
            cell.bannerView.titleLabel.text = appID.name
            cell.bannerView.subtitleLabel.text = appID.bundleIdentifier
            cell.bannerView.subtitleLabel.numberOfLines = 2
            
            let attributedBundleIdentifier = NSMutableAttributedString(string: appID.bundleIdentifier.lowercased(), attributes: [.accessibilitySpeechPunctuation: true])
            
            if let team = appID.team, let range = attributedBundleIdentifier.string.range(of: team.identifier.lowercased()), #available(iOS 13, *)
            {
                // Prefer to speak the team ID one character at a time.
                let nsRange = NSRange(range, in: attributedBundleIdentifier.string)
                attributedBundleIdentifier.addAttributes([.accessibilitySpeechSpellOut: true], range: nsRange)
            }
            
            attributedAccessibilityLabel.append(attributedBundleIdentifier)
            cell.bannerView.accessibilityAttributedLabel = attributedAccessibilityLabel
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        
        return dataSource
    }
    
    @objc func fetchAppIDs()
    {
        guard !self.isLoading else { return }
        self.isLoading = true
        
        AppManager.shared.fetchAppIDs { (result) in
            do
            {
                let (_, context) = try result.get()
                try context.save()
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    func update()
    {
        if !self.isLoading
        {
            self.collectionView.refreshControl?.endRefreshing()
            self.activityIndicatorBarButtonItem.isIndicatingActivity = false
        }
    }
}

extension AppIDsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: collectionView.bounds.width, height: 80)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let indexPath = IndexPath(row: 0, section: section)
        let headerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader, at: indexPath)
        
        // Use this view to calculate the optimal size based on the collection view's width
        let size = headerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
                                                      withHorizontalFittingPriority: .required, // Width is fixed
                                                      verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        return CGSize(width: collectionView.bounds.width, height: 50)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        switch kind
        {
        case UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! TextCollectionReusableView
            headerView.layoutMargins.left = self.view.layoutMargins.left
            headerView.layoutMargins.right = self.view.layoutMargins.right
            
            if let activeTeam = DatabaseManager.shared.activeTeam(), activeTeam.type == .free
            {
                let text = NSLocalizedString("""
                Each app and app extension installed with AltStore must register an App ID with Apple. Apple limits free developer accounts to 10 App IDs at a time.

                **App IDs can't be deleted**, but they do expire after one week. AltStore will automatically renew App IDs for all active apps once they've expired.
                """, comment: "")
                
                let attributedText = NSAttributedString(markdownRepresentation: text, attributes: [.font: headerView.textLabel.font as Any])
                headerView.textLabel.attributedText = attributedText
            }
            else
            {
                headerView.textLabel.text = NSLocalizedString("""
                Each app and app extension installed with AltStore must register an App ID with Apple.
                
                App IDs for paid developer accounts never expire, and there is no limit to how many you can create.
                """, comment: "")
            }
            
            return headerView
            
        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Footer", for: indexPath) as! TextCollectionReusableView
            
            let count = self.dataSource.itemCount
            if count == 1
            {
                footerView.textLabel.text = NSLocalizedString("1 App ID", comment: "")
            }
            else
            {
                footerView.textLabel.text = String(format: NSLocalizedString("%@ App IDs", comment: ""), NSNumber(value: count))
            }
            
            return footerView
            
        default: fatalError()
        }
    }
}
