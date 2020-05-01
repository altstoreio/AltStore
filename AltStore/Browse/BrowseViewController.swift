//
//  BrowseViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

import Nuke

class BrowseViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)
    
    private let prototypeCell = BrowseCollectionViewCell.instantiate(with: BrowseCollectionViewCell.nib!)!
    
    private var loadingState: LoadingState = .loading {
        didSet {
            self.update()
        }
    }
    
    private var cachedItemSizes = [String: CGSize]()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        #if BETA
        self.dataSource.searchController.searchableKeyPaths = [#keyPath(InstalledApp.name)]
        self.navigationItem.searchController = self.dataSource.searchController
        #else
        // Hide Sources button for public version while in beta.
        self.navigationItem.rightBarButtonItem = nil
        #endif
        
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(BrowseCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.registerForPreviewing(with: self, sourceView: self.collectionView)
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchSource()
        self.updateDataSource()
    }
    
    @IBAction private func unwindToBrowseViewController(_ segue: UIStoryboardSegue)
    {
        self.fetchSource()
    }
}

private extension BrowseViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>
    {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID)
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
            let cell = cell as! BrowseCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.subtitleLabel.text = app.subtitle
            cell.imageURLs = Array(app.screenshotURLs.prefix(2))
            cell.bannerView.titleLabel.text = app.name
            cell.bannerView.subtitleLabel.text = app.developerName
            cell.bannerView.betaBadgeView.isHidden = !app.isBeta
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            
            cell.bannerView.button.addTarget(self, action: #selector(BrowseViewController.performAppAction(_:)), for: .primaryActionTriggered)
            cell.bannerView.button.activityIndicatorView.style = .white
            
            // Explicitly set to false to ensure we're starting from a non-activity indicating state.
            // Otherwise, cell reuse can mess up some cached values.
            cell.bannerView.button.isIndicatingActivity = false
            
            let tintColor = app.tintColor ?? .altPrimary
            cell.tintColor = tintColor
            
            if app.installedApp == nil
            {
                cell.bannerView.button.setTitle(NSLocalizedString("FREE", comment: ""), for: .normal)
                
                let progress = AppManager.shared.installationProgress(for: app)
                cell.bannerView.button.progress = progress
                
                if Date() < app.versionDate
                {
                    cell.bannerView.button.countdownDate = app.versionDate
                }
                else
                {
                    cell.bannerView.button.countdownDate = nil
                }
            }
            else
            {
                cell.bannerView.button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
                cell.bannerView.button.progress = nil
                cell.bannerView.button.countdownDate = nil
            }
        }
        dataSource.prefetchHandler = { (storeApp, indexPath, completionHandler) -> Foundation.Operation? in
            let iconURL = storeApp.iconURL
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: iconURL, progress: nil, completion: { (response, error) in
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
            let cell = cell as! BrowseCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        dataSource.placeholderView = self.placeholderView
        
        return dataSource
    }
    
    func updateDataSource()
    {
        if let patreonAccount = DatabaseManager.shared.patreonAccount(), patreonAccount.isPatron, PatreonAPI.shared.isAuthenticated
        {
            self.dataSource.predicate = nil
        }
        else
        {
            self.dataSource.predicate = NSPredicate(format: "%K == NO", #keyPath(StoreApp.isBeta))
        }
    }
    
    func fetchSource()
    {
        self.loadingState = .loading
        
        AppManager.shared.fetchSources() { (result) in
            do
            {
                let sources = try result.get()
                try sources.first?.managedObjectContext?.save()
                
                DispatchQueue.main.async {
                    self.loadingState = .finished(.success(()))
                }
            }
            catch let error as NSError
            {
                DispatchQueue.main.async {
                    if self.dataSource.itemCount > 0
                    {
                        let error = error.withLocalizedFailure(NSLocalizedString("Failed to Fetch Sources", comment: ""))
                        
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                    }
                    
                    self.loadingState = .finished(.failure(error))
                }
            }
        }
    }
    
    func update()
    {
        switch self.loadingState
        {
        case .loading:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
            
            self.placeholderView.activityIndicatorView.startAnimating()
            
        case .finished(.failure(let error)):
            self.placeholderView.textLabel.isHidden = false
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch Apps", comment: "")
            self.placeholderView.detailTextLabel.text = error.localizedDescription
            
            self.placeholderView.activityIndicatorView.stopAnimating()
            
        case .finished(.success):
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = true
            
            self.placeholderView.activityIndicatorView.stopAnimating()
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
    
    func install(_ app: StoreApp, at indexPath: IndexPath)
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
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                
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
        
        let layout = self.prototypeCell.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let padding = (layout.minimumInteritemSpacing * (maxVisibleScreenshots - 1)) + layout.sectionInset.left + layout.sectionInset.right

        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)

        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        widthConstraint.isActive = true
        defer { widthConstraint.isActive = false }

        // Manually update cell width & layout so we can accurately calculate screenshot sizes.
        self.prototypeCell.frame.size.width = widthConstraint.constant
        self.prototypeCell.layoutIfNeeded()
        
        let collectionViewWidth = self.prototypeCell.screenshotsCollectionView.bounds.width
        let screenshotWidth = ((collectionViewWidth - padding) / maxVisibleScreenshots).rounded(.down)
        let screenshotHeight = screenshotWidth * aspectRatio

        let heightConstraint = self.prototypeCell.screenshotsCollectionView.heightAnchor.constraint(equalToConstant: screenshotHeight)
        heightConstraint.priority = .defaultHigh // Prevent temporary unsatisfiable constraints error.
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
