//
//  BrowseViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class BrowseViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private let prototypeCell = BrowseCollectionViewCell.instantiate(with: BrowseCollectionViewCell.nib!)!
    
    private var cachedItemSizes = [String: CGSize]()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(BrowseCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.registerForPreviewing(with: self, sourceView: self.collectionView)
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchSource()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "showApp" else { return }
        
        guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        
        let appViewController = segue.destination as! AppViewController
        appViewController.app = app
    }
}

private extension BrowseViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<App, UIImage>
    {
        let fetchRequest = App.fetchRequest() as NSFetchRequest<App>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \App.sortIndex, ascending: true), NSSortDescriptor(keyPath: \App.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        if let source = Source.fetchAltStoreSource(in: DatabaseManager.shared.viewContext)
        {
            fetchRequest.predicate = NSPredicate(format: "%K != %@ AND %K == %@", #keyPath(App.bundleIdentifier), App.altstoreAppID, #keyPath(App.source), source)
        }
        else
        {
            fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(App.bundleIdentifier), App.altstoreAppID)
        }
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<App, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
            let cell = cell as! BrowseCollectionViewCell
            cell.nameLabel.text = app.name
            cell.developerLabel.text = app.developerName
            cell.subtitleLabel.text = app.subtitle
            cell.imageNames = Array(app.screenshotNames.prefix(3))
            cell.appIconImageView.image = UIImage(named: app.iconName)
            
            cell.actionButton.addTarget(self, action: #selector(BrowseViewController.performAppAction(_:)), for: .primaryActionTriggered)
            cell.actionButton.activityIndicatorView.style = .white
            
            // Explicitly set to false to ensure we're starting from a non-activity indicating state.
            // Otherwise, cell reuse can mess up some cached values.
            cell.actionButton.isIndicatingActivity = false
            
            let tintColor = app.tintColor ?? .altGreen
            cell.tintColor = tintColor
            
            if app.installedApp == nil
            {
                cell.actionButton.setTitle(NSLocalizedString("FREE", comment: ""), for: .normal)
                
                let progress = AppManager.shared.installationProgress(for: app)
                cell.actionButton.progress = progress
                cell.actionButton.isInverted = false
            }
            else
            {
                cell.actionButton.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
                cell.actionButton.progress = nil
                cell.actionButton.isInverted = true
            }
        }
        
        return dataSource
    }
    
    func fetchSource()
    {
        AppManager.shared.fetchSource() { (result) in
            do
            {                
                let source = try result.get()
                try source.managedObjectContext?.save()
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                }
            }
        }
    }
}

private extension BrowseViewController
{
    @IBAction func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        
        if let installedApp = app.installedApp
        {
            self.open(installedApp)
        }
        else
        {
            self.install(app, at: indexPath)
        }
    }
    
    func install(_ app: App, at indexPath: IndexPath)
    {
        let previousProgress = AppManager.shared.installationProgress(for: app)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        _ = AppManager.shared.install(app, presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled): break // Ignore
                case .failure(let error):
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                
                case .success: print("Installed app:", app.bundleIdentifier)
                }
                
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        
        self.collectionView.reloadItems(at: [indexPath])
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension BrowseViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let item = self.dataSource.item(at: indexPath)

        if let previousSize = self.cachedItemSizes[item.bundleIdentifier]
        {
            return previousSize
        }

        let maxVisibleScreenshots = 2 as CGFloat
        let aspectRatio: CGFloat = 16.0 / 9.0
        
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let padding = (layout.minimumInteritemSpacing * (maxVisibleScreenshots - 1))

        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)

        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        widthConstraint.isActive = true
        defer { widthConstraint.isActive = false }

        self.prototypeCell.layoutIfNeeded()
        
        let collectionViewWidth = self.prototypeCell.screenshotsCollectionView.bounds.width
        let screenshotWidth = ((collectionViewWidth - padding) / maxVisibleScreenshots).rounded(.down)
        let screenshotHeight = screenshotWidth * aspectRatio

        let heightConstraint = self.prototypeCell.screenshotsCollectionView.heightAnchor.constraint(equalToConstant: screenshotHeight)
        heightConstraint.isActive = true
        defer { heightConstraint.isActive = false }

        let itemSize = self.prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.cachedItemSizes[item.bundleIdentifier] = itemSize
        return itemSize
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let app = self.dataSource.item(at: indexPath)
        
        let appViewController = AppViewController.makeAppViewController(app: app)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
}

extension BrowseViewController: UIViewControllerPreviewingDelegate
{
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        guard
            let indexPath = self.collectionView.indexPathForItem(at: location),
            let cell = self.collectionView.cellForItem(at: indexPath)
        else { return nil }
        
        previewingContext.sourceRect = cell.frame
        
        let app = self.dataSource.item(at: indexPath)
        
        let appViewController = AppViewController.makeAppViewController(app: app)
        return appViewController
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        self.navigationController?.pushViewController(viewControllerToCommit, animated: true)
    }
}
