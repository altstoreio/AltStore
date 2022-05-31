//
//  PatreonViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices
import AuthenticationServices

import AltStoreCore
import Roxas

extension PatreonViewController
{
    private enum Section: Int, CaseIterable
    {
        case about
        case patrons
    }
}

class PatreonViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var patronsDataSource = self.makePatronsDataSource()
    
    private var prototypeAboutHeader: AboutPatreonHeaderView!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let aboutHeaderNib = UINib(nibName: "AboutPatreonHeaderView", bundle: nil)
        self.prototypeAboutHeader = aboutHeaderNib.instantiate(withOwner: nil, options: nil)[0] as? AboutPatreonHeaderView
        
        self.collectionView.dataSource = self.dataSource
        
        self.collectionView.register(aboutHeaderNib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "AboutHeader")
        self.collectionView.register(PatronsHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "PatronsHeader")
        self.collectionView.register(PatronsFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "PatronsFooter")
        
        NotificationCenter.default.addObserver(self, selector: #selector(PatreonViewController.didUpdatePatrons(_:)), name: AppManager.didUpdatePatronsNotification, object: nil)
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchPatrons()
        
        self.update()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let layout = self.collectionViewLayout as! UICollectionViewFlowLayout
        
        var itemWidth = (self.collectionView.bounds.width - (layout.sectionInset.left + layout.sectionInset.right + layout.minimumInteritemSpacing)) / 2
        itemWidth.round(.down)
        
        layout.itemSize = CGSize(width: itemWidth, height: layout.itemSize.height)
    }
}

private extension PatreonViewController
{
    func makeDataSource() -> RSTCompositeCollectionViewDataSource<ManagedPatron>
    {
        let aboutDataSource = RSTDynamicCollectionViewDataSource<ManagedPatron>()
        aboutDataSource.numberOfSectionsHandler = { 1 }
        aboutDataSource.numberOfItemsHandler = { _ in 0 }
        
        let dataSource = RSTCompositeCollectionViewDataSource<ManagedPatron>(dataSources: [aboutDataSource, self.patronsDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makePatronsDataSource() -> RSTFetchedResultsCollectionViewDataSource<ManagedPatron>
    {
        let fetchRequest: NSFetchRequest<ManagedPatron> = ManagedPatron.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(ManagedPatron.name), ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))]
        
        let patronsDataSource = RSTFetchedResultsCollectionViewDataSource<ManagedPatron>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        patronsDataSource.cellConfigurationHandler = { (cell, patron, indexPath) in
            let cell = cell as! PatronCollectionViewCell
            cell.textLabel.text = patron.name
        }
        
        return patronsDataSource
    }
    
    func update()
    {
        self.collectionView.reloadData()
    }
    
    func prepare(_ headerView: AboutPatreonHeaderView)
    {
        headerView.layoutMargins = self.view.layoutMargins
        
        headerView.supportButton.addTarget(self, action: #selector(PatreonViewController.openPatreonURL(_:)), for: .primaryActionTriggered)
        headerView.accountButton.removeTarget(self, action: nil, for: .primaryActionTriggered)
        
        let defaultSupportButtonTitle = NSLocalizedString("Become a patron", comment: "")
        let isPatronSupportButtonTitle = NSLocalizedString("View Patreon", comment: "")
        
        let defaultText = NSLocalizedString("""
        Hey y'all,
        
        You can support future development of our apps by donating to us on Patreon. In return, you'll receive access to the beta versions of our apps and be among the first to try the latest features.
        
        Thanks for all your support 💜
        Riley & Shane
        """, comment: "")
        
        let isPatronText = NSLocalizedString("""
        Hey ,
        
        You’re the best. Your account was linked successfully, so you now have access to the beta versions of all of our apps. You can find them all in the Browse tab.
        
        Thanks for all of your support. Enjoy!
        Riley & Shane
        """, comment: "")
        
        if let account = DatabaseManager.shared.patreonAccount(), PatreonAPI.shared.isAuthenticated
        {
            headerView.accountButton.addTarget(self, action: #selector(PatreonViewController.signOut(_:)), for: .primaryActionTriggered)
            headerView.accountButton.setTitle(String(format: NSLocalizedString("Unlink %@", comment: ""), account.name), for: .normal)
            
            if account.isPatron
            {
                headerView.supportButton.setTitle(isPatronSupportButtonTitle, for: .normal)
                
                let font = UIFont.systemFont(ofSize: 16)
                
                let attributedText = NSMutableAttributedString(string: isPatronText, attributes: [.font: font,
                                                                                                  .foregroundColor: UIColor.white])
                
                let boldedName = NSAttributedString(string: account.firstName ?? account.name,
                                                    attributes: [.font: UIFont.boldSystemFont(ofSize: font.pointSize),
                                                                 .foregroundColor: UIColor.white])
                attributedText.insert(boldedName, at: 4)
                
                headerView.textView.attributedText = attributedText
            }
            else
            {
                headerView.supportButton.setTitle(defaultSupportButtonTitle, for: .normal)
                headerView.textView.text = defaultText
            }
        }
        else
        {
            headerView.accountButton.addTarget(self, action: #selector(PatreonViewController.authenticate(_:)), for: .primaryActionTriggered)
            
            headerView.supportButton.setTitle(defaultSupportButtonTitle, for: .normal)
            headerView.accountButton.setTitle(NSLocalizedString("Link Patreon account", comment: ""), for: .normal)
            
            headerView.textView.text = defaultText
        }
    }
}

private extension PatreonViewController
{
    @objc func fetchPatrons()
    {
        AppManager.shared.updatePatronsIfNeeded()
        self.update()
    }
    
    @objc func openPatreonURL(_ sender: UIButton)
    {
        let patreonURL = URL(string: "https://altstore.io/patreon")!
        
        let safariViewController = SFSafariViewController(url: patreonURL)
        safariViewController.preferredControlTintColor = self.view.tintColor
        self.present(safariViewController, animated: true, completion: nil)
    }
    
    @IBAction func authenticate(_ sender: UIBarButtonItem)
    {
        PatreonAPI.shared.authenticate { (result) in
            do
            {
                let account = try result.get()
                try account.managedObjectContext?.save()
                
                DispatchQueue.main.async {
                    self.update()
                }
            }
            catch ASWebAuthenticationSessionError.canceledLogin
            {
                // Ignore
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }
        }
    }
    
    @IBAction func signOut(_ sender: UIBarButtonItem)
    {
        func signOut()
        {
            PatreonAPI.shared.signOut { (result) in
                do
                {
                    try result.get()
                    
                    DispatchQueue.main.async {
                        self.update()
                    }
                }
                catch
                {
                    DispatchQueue.main.async {
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                    }
                }
            }
        }
        
        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to unlink your Patreon account?", comment: ""), message: NSLocalizedString("You will no longer have access to beta versions of apps.", comment: ""), preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Unlink Patreon Account", comment: ""), style: .destructive) { _ in signOut() })
        alertController.addAction(.cancel)
        self.present(alertController, animated: true, completion: nil)
    }
    
    @objc func didUpdatePatrons(_ notification: Notification)
    {
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }
}

extension PatreonViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .about:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "AboutHeader", for: indexPath) as! AboutPatreonHeaderView
            self.prepare(headerView)
            return headerView
            
        case .patrons:
            if kind == UICollectionView.elementKindSectionHeader
            {
                let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "PatronsHeader", for: indexPath) as! PatronsHeaderView
                headerView.textLabel.text = NSLocalizedString("Special thanks to...", comment: "")
                return headerView
            }
            else
            {
                let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "PatronsFooter", for: indexPath) as! PatronsFooterView
                footerView.button.isIndicatingActivity = false
                footerView.button.isHidden = false
                footerView.button.addTarget(self, action: #selector(PatreonViewController.fetchPatrons), for: .primaryActionTriggered)
                
                if self.patronsDataSource.itemCount > 0
                {
                    footerView.button.isHidden = true
                }
                else
                {
                    switch AppManager.shared.updatePatronsResult
                    {
                    case .none: footerView.button.isIndicatingActivity = true
                    case .success?: footerView.button.isHidden = true
                    case .failure?: footerView.button.setTitle(NSLocalizedString("Error Loading Patrons", comment: ""), for: .normal)
                    }
                }
                
                return footerView
            }
        }
    }
}

extension PatreonViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        switch section
        {
        case .about:
            let widthConstraint = self.prototypeAboutHeader.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
            NSLayoutConstraint.activate([widthConstraint])
            defer { NSLayoutConstraint.deactivate([widthConstraint]) }
            
            self.prepare(self.prototypeAboutHeader)
            
            let size = self.prototypeAboutHeader.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            return size
            
        case .patrons:
            return CGSize(width: 320, height: 20)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        switch section
        {
        case .about: return .zero
        case .patrons: return CGSize(width: 320, height: 20)
        }
    }
}
