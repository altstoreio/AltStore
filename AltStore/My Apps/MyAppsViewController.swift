//
//  MyAppsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltKit
import Roxas

import AltSign

import Nuke

private let maximumCollapsedUpdatesCount = 2

extension MyAppsViewController
{
    private enum Section: Int, CaseIterable
    {
        case noUpdates
        case updates
        case installedApps
    }
}

class MyAppsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var noUpdatesDataSource = self.makeNoUpdatesDataSource()
    private lazy var updatesDataSource = self.makeUpdatesDataSource()
    private lazy var installedAppsDataSource = self.makeInstalledAppsDataSource()
    
    private var prototypeUpdateCell: UpdateCollectionViewCell!
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var sideloadingProgressView: UIProgressView!
    
    // State
    private var isUpdateSectionCollapsed = true
    private var expandedAppUpdates = Set<String>()
    private var isRefreshingAllApps = false
    private var refreshGroup: OperationGroup?
    private var sideloadingProgress: Progress?
    
    // Cache
    private var cachedUpdateSizes = [String: CGSize]()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.didFetchSource(_:)), name: AppManager.didFetchSourceNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        #if !BETA
        // Set leftBarButtonItem to invisible UIBarButtonItem so we can still use it
        // to show an activity indicator while sideloading whitelisted apps.
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        #endif
        
        if #available(iOS 13.0, *)
        {
            self.navigationItem.leftBarButtonItem?.activityIndicatorView.style = .medium
        }
        
        // Allows us to intercept delegate callbacks.
        self.updatesDataSource.fetchedResultsController.delegate = self
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
                
        self.prototypeUpdateCell = UpdateCollectionViewCell.instantiate(with: UpdateCollectionViewCell.nib!)
        self.prototypeUpdateCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(UpdateCollectionViewCell.nib, forCellWithReuseIdentifier: "UpdateCell")
        self.collectionView.register(UpdatesCollectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader")
        
        self.sideloadingProgressView = UIProgressView(progressViewStyle: .bar)
        self.sideloadingProgressView.translatesAutoresizingMaskIntoConstraints = false
        self.sideloadingProgressView.progressTintColor = .altPrimary
        self.sideloadingProgressView.progress = 0
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            navigationBar.addSubview(self.sideloadingProgressView)
            NSLayoutConstraint.activate([self.sideloadingProgressView.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
                                         self.sideloadingProgressView.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),
                                         self.sideloadingProgressView.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor)])
        }
        
        // Gestures
        self.longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(MyAppsViewController.handleLongPressGesture(_:)))
        self.collectionView.addGestureRecognizer(self.longPressGestureRecognizer)
        
        self.registerForPreviewing(with: self, sourceView: self.collectionView)
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.updateDataSource()
        
        #if BETA
        self.fetchAppIDs()
        #endif
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard let identifier = segue.identifier else { return }
        
        switch identifier
        {
        case "showApp", "showUpdate":
            guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return }
            
            let installedApp = self.dataSource.item(at: indexPath)
            
            let appViewController = segue.destination as! AppViewController
            appViewController.app = installedApp.storeApp
            
        default: break
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool
    {
        guard identifier == "showApp" else { return true }
        
        guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return true }
        
        let installedApp = self.dataSource.item(at: indexPath)
        return !installedApp.isSideloaded
    }
    
    @IBAction func unwindToMyAppsViewController(_ segue: UIStoryboardSegue)
    {
    }
}

private extension MyAppsViewController
{
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(dataSources: [self.noUpdatesDataSource, self.updatesDataSource, self.installedAppsDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makeNoUpdatesDataSource() -> RSTDynamicCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let dynamicDataSource = RSTDynamicCollectionViewPrefetchingDataSource<InstalledApp, UIImage>()
        dynamicDataSource.numberOfSectionsHandler = { 1 }
        dynamicDataSource.numberOfItemsHandler = { _ in self.updatesDataSource.itemCount == 0 ? 1 : 0 }
        dynamicDataSource.cellIdentifierHandler = { _ in "NoUpdatesCell" }
        dynamicDataSource.cellConfigurationHandler = { (cell, _, indexPath) in
            let cell = cell as! NoUpdatesCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.blurView.layer.cornerRadius = 20
            cell.blurView.layer.masksToBounds = true
            cell.blurView.backgroundColor = .altPrimary
        }
        
        return dynamicDataSource
    }
    
    func makeUpdatesDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.updatesFetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.storeApp?.versionDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.liveFetchLimit = maximumCollapsedUpdatesCount
        dataSource.cellIdentifierHandler = { _ in "UpdateCell" }
        dataSource.cellConfigurationHandler = { [weak self] (cell, installedApp, indexPath) in
            guard let self = self else { return }
            guard let app = installedApp.storeApp else { return }
            
            let cell = cell as! UpdateCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.tintColor = app.tintColor ?? .altPrimary
            cell.versionDescriptionTextView.text = app.versionDescription
            
            cell.bannerView.titleLabel.text = app.name
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            cell.bannerView.betaBadgeView.isHidden = !app.isBeta
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.button.addTarget(self, action: #selector(MyAppsViewController.updateApp(_:)), for: .primaryActionTriggered)
            
            if self.expandedAppUpdates.contains(app.bundleIdentifier)
            {
                cell.mode = .expanded
            }
            else
            {
                cell.mode = .collapsed
            }
            
            cell.versionDescriptionTextView.moreButton.addTarget(self, action: #selector(MyAppsViewController.toggleUpdateCellMode(_:)), for: .primaryActionTriggered)
            
            let progress = AppManager.shared.installationProgress(for: app)
            cell.bannerView.button.progress = progress
            
            cell.bannerView.subtitleLabel.text = Date().relativeDateString(since: app.versionDate, dateFormatter: self.dateFormatter)
            
            cell.setNeedsLayout()
        }
        dataSource.prefetchHandler = { (installedApp, indexPath, completionHandler) in
            guard let iconURL = installedApp.storeApp?.iconURL else { return nil }
            
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
            let cell = cell as! UpdateCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
    
    func makeInstalledAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.storeApp)]
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.refreshedDate, ascending: false),
                                        NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            let tintColor = installedApp.storeApp?.tintColor ?? .altPrimary
            
            let cell = cell as! InstalledAppCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
            
            cell.bannerView.iconImageView.isIndicatingActivity = true
            cell.bannerView.betaBadgeView.isHidden = !(installedApp.storeApp?.isBeta ?? false)
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.button.addTarget(self, action: #selector(MyAppsViewController.refreshApp(_:)), for: .primaryActionTriggered)
            
            let currentDate = Date()
            
            let numberOfDays = installedApp.expirationDate.numberOfCalendarDays(since: currentDate)
            
            if numberOfDays == 1
            {
                cell.bannerView.button.setTitle(NSLocalizedString("1 DAY", comment: ""), for: .normal)
            }
            else
            {
                cell.bannerView.button.setTitle(String(format: NSLocalizedString("%@ DAYS", comment: ""), NSNumber(value: numberOfDays)), for: .normal)
            }
                                    
            cell.bannerView.titleLabel.text = installedApp.name
            cell.bannerView.subtitleLabel.text = installedApp.storeApp?.developerName ?? NSLocalizedString("Sideloaded", comment: "")
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
            
            switch numberOfDays
            {
            case 2...3: cell.bannerView.button.tintColor = .refreshOrange
            case 4...5: cell.bannerView.button.tintColor = .refreshYellow
            case 6...: cell.bannerView.button.tintColor = .refreshGreen
            default: cell.bannerView.button.tintColor = .refreshRed
            }
            
            if let refreshGroup = self.refreshGroup, let progress = refreshGroup.progress(for: installedApp), progress.fractionCompleted < 1.0
            {
                cell.bannerView.button.progress = progress
            }
            else
            {
                cell.bannerView.button.progress = nil
            }
        }
        dataSource.prefetchHandler = { (item, indexPath, completion) in
            let fileURL = item.fileURL
            
            return BlockOperation {
                guard let application = ALTApplication(fileURL: fileURL) else {
                    completion(nil, OperationError.invalidApp)
                    return
                }
                
                let icon = application.icon
                completion(icon, nil)
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! InstalledAppCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
        }
        
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
            self.dataSource.predicate = NSPredicate(format: "%K == nil OR %K == NO OR %K == %@",
                                                    #keyPath(InstalledApp.storeApp),
                                                    #keyPath(InstalledApp.storeApp.isBeta),
                                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        }
    }
}

private extension MyAppsViewController
{
    func update()
    {
        if self.updatesDataSource.itemCount > 0
        {
            self.navigationController?.tabBarItem.badgeValue = String(describing: self.updatesDataSource.itemCount)
            UIApplication.shared.applicationIconBadgeNumber = Int(self.updatesDataSource.itemCount)
        }
        else
        {
            self.navigationController?.tabBarItem.badgeValue = nil
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        
        if self.isViewLoaded
        {
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: Section.updates.rawValue))
            }
        }        
    }
    
    func fetchAppIDs()
    {
        AppManager.shared.fetchAppIDs { (result) in
            do
            {
                let (_, context) = try result.get()
                try context.save()
            }
            catch
            {
                print("Failed to fetch App IDs.", error)
            }
        }
    }
    
    func refresh(_ installedApps: [InstalledApp], completionHandler: @escaping (Result<[String : Result<InstalledApp, Error>], Error>) -> Void)
    {
        func refresh()
        {
            let group = AppManager.shared.refresh(installedApps, presentingViewController: self, group: self.refreshGroup)
            group.completionHandler = { (result) in
                DispatchQueue.main.async {
                    switch result
                    {
                    case .failure(let error):
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                        
                    case .success(let results):
                        let failures = results.compactMapValues { (result) -> Error? in
                            switch result
                            {
                            case .failure(OperationError.cancelled): return nil
                            case .failure(let error): return error
                            case .success: return nil
                            }
                        }
                        
                        guard !failures.isEmpty else { break }
                        
                        let toastView: ToastView
                        
                        if let failure = failures.first, results.count == 1
                        {
                            toastView = ToastView(error: failure.value)
                        }
                        else
                        {
                            let localizedText: String
                            
                            if failures.count == 1
                            {
                                localizedText = NSLocalizedString("Failed to refresh 1 app.", comment: "")
                            }
                            else
                            {
                                localizedText = String(format: NSLocalizedString("Failed to refresh %@ apps.", comment: ""), NSNumber(value: failures.count))
                            }
                            
                            let detailText = failures.first?.value.localizedDescription
                            
                            toastView = ToastView(text: localizedText, detailText: detailText)
                            toastView.preferredDuration = 2.0
                        }
                        
                        toastView.show(in: self)
                    }
                    
                    self.refreshGroup = nil
                    completionHandler(result)
                }
            }
            
            self.refreshGroup = group
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: Section.installedApps.rawValue))
            }
        }
        
        if installedApps.contains(where: { $0.bundleIdentifier == StoreApp.altstoreAppID })
        {
            let alertController = UIAlertController(title: NSLocalizedString("Refresh AltStore?", comment: ""), message: NSLocalizedString("AltStore will quit when it is finished refreshing.", comment: ""), preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: RSTSystemLocalizedString("Cancel"), style: .cancel) { (action) in
                completionHandler(.failure(OperationError.cancelled))
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Refresh", comment: ""), style: .default) { (action) in
                refresh()
            })
            self.present(alertController, animated: true, completion: nil)
        }
        else
        {
            refresh()
        }
    }
}

private extension MyAppsViewController
{
    @IBAction func toggleAppUpdates(_ sender: UIButton)
    {
        let visibleCells = self.collectionView.visibleCells
        
        self.collectionView.performBatchUpdates({
            
            self.isUpdateSectionCollapsed.toggle()
            
            UIView.animate(withDuration: 0.3, animations: {
                if self.isUpdateSectionCollapsed
                {
                    self.updatesDataSource.liveFetchLimit = maximumCollapsedUpdatesCount
                    self.expandedAppUpdates.removeAll()
                    
                    for case let cell as UpdateCollectionViewCell in visibleCells
                    {
                        cell.mode = .collapsed
                    }
                    
                    self.cachedUpdateSizes.removeAll()
                    
                    sender.titleLabel?.transform = .identity
                }
                else
                {
                    self.updatesDataSource.liveFetchLimit = 0
                    
                    sender.titleLabel?.transform = CGAffineTransform.identity.rotated(by: .pi)
                }
            })
            
            self.collectionView.collectionViewLayout.invalidateLayout()
            
        }, completion: nil)
    }
    
    @IBAction func toggleUpdateCellMode(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let cell = self.collectionView.cellForItem(at: indexPath) as? UpdateCollectionViewCell
        
        if self.expandedAppUpdates.contains(installedApp.bundleIdentifier)
        {
            self.expandedAppUpdates.remove(installedApp.bundleIdentifier)
            cell?.mode = .collapsed
        }
        else
        {
            self.expandedAppUpdates.insert(installedApp.bundleIdentifier)
            cell?.mode = .expanded
        }
        
        self.cachedUpdateSizes[installedApp.bundleIdentifier] = nil
        
        self.collectionView.performBatchUpdates({
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }
    
    @IBAction func refreshApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let previousProgress = AppManager.shared.refreshProgress(for: installedApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        self.refresh([installedApp]) { (result) in
            // If an error occured, reload the section so the progress bar is no longer visible.
            if result.error != nil || result.value?.values.contains(where: { $0.error != nil }) == true
            {
                DispatchQueue.main.async {
                    self.collectionView.reloadSections(IndexSet(integer: Section.installedApps.rawValue))
                }
            }
            
            print("Finished refreshing with result:", result.error?.localizedDescription ?? "success")
        }
    }
    
    @IBAction func refreshAllApps(_ sender: UIBarButtonItem)
    {
        self.isRefreshingAllApps = true
        self.collectionView.collectionViewLayout.invalidateLayout()

        let installedApps = InstalledApp.fetchAppsForRefreshingAll(in: DatabaseManager.shared.viewContext)
        
        self.refresh(installedApps) { (result) in
            DispatchQueue.main.async {
                self.isRefreshingAllApps = false
                self.collectionView.reloadSections(IndexSet(integer: Section.installedApps.rawValue))
            }
        }
    }
    
    @IBAction func updateApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        guard let storeApp = self.dataSource.item(at: indexPath).storeApp else { return }
        
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        _ = AppManager.shared.install(storeApp, presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled):
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                    
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .success:
                    print("Updated app:", storeApp.bundleIdentifier)
                    // No need to reload, since the the update cell is gone now.
                }
                
                self.update()
            }
        }
        
        self.collectionView.reloadItems(at: [indexPath])
    }
    
    @IBAction func sideloadApp(_ sender: UIBarButtonItem)
    {
        self.presentSideloadingAlert { (shouldContinue) in
            guard shouldContinue else { return }
            
            let iOSAppUTI = "com.apple.itunes.ipa" // Declared by the system.
            
            let documentPickerViewController = UIDocumentPickerViewController(documentTypes: [iOSAppUTI], in: .import)
            documentPickerViewController.delegate = self
            self.present(documentPickerViewController, animated: true, completion: nil)
        }
    }
    
    func presentSideloadingAlert(completion: @escaping (Bool) -> Void)
    {
        let alertController = UIAlertController(title: NSLocalizedString("Sideload Apps (Beta)", comment: ""), message: NSLocalizedString("If you encounter an app that is not able to be sideloaded, please report the app to support@altstore.io.", comment: ""), preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: RSTSystemLocalizedString("OK"), style: .default, handler: { (action) in
            completion(true)
        }))
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: { (action) in
            completion(false)
        }))
        self.present(alertController, animated: true, completion: nil)
    }
    
    func sideloadApp(at fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
        
        DispatchQueue.global().async {
            let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
            
            do
            {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                
                let unzippedApplicationURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: temporaryDirectory)
                
                guard let application = ALTApplication(fileURL: unzippedApplicationURL) else { throw OperationError.invalidApp }
                
                #if !BETA
                guard AppManager.whitelistedSideloadingBundleIDs.contains(application.bundleIdentifier) else { throw OperationError.sideloadingAppNotSupported(application) }
                #endif
                
                self.sideloadingProgress = AppManager.shared.install(application, presentingViewController: self) { (result) in
                    try? FileManager.default.removeItem(at: temporaryDirectory)
                    
                    DispatchQueue.main.async {
                        if let error = result.error
                        {
                            let toastView = ToastView(error: error)
                            toastView.show(in: self)
                        }
                        else
                        {
                            print("Successfully installed app:", application.bundleIdentifier)
                        }
                        
                        self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
                        self.sideloadingProgressView.observedProgress = nil
                        self.sideloadingProgressView.setHidden(true, animated: true)
                        
                        completion(.success(()))
                    }
                }
                
                DispatchQueue.main.async {
                    self.sideloadingProgressView.progress = 0
                    self.sideloadingProgressView.isHidden = false
                    self.sideloadingProgressView.observedProgress = self.sideloadingProgress
                }
            }
            catch
            {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                DispatchQueue.main.async {
                    self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
                    
                    if let localizedError = error as? OperationError, case OperationError.sideloadingAppNotSupported = localizedError
                    {
                        let message = NSLocalizedString("""
                        Sideloading apps is in beta, and is currently limited to a small number of apps. This restriction is temporary, and you will be able to sideload any app once the feature is finished.

                        In the meantime, you can help us beta test sideloading apps by becoming a Patron.
                        """, comment: "")
                        
                        let alertController = UIAlertController(title: localizedError.localizedDescription, message: message, preferredStyle: .alert)
                        alertController.addAction(.cancel)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Become a Patron", comment: ""), style: .default, handler: { (action) in
                            NotificationCenter.default.post(name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
                        }))
                        
                        self.present(alertController, animated: true, completion: nil)
                    }
                    else
                    {
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                    }
                }
                
                completion(.failure(error))
            }
        }
    }
    
    @objc func presentAlert(for installedApp: InstalledApp)
    {
        let alertController = UIAlertController(title: nil, message: NSLocalizedString("Removing a sideloaded app only removes it from AltStore. You must also delete it from the home screen to fully uninstall the app.", comment: ""), preferredStyle: .actionSheet)
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: ""), style: .destructive, handler: { (action) in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                context.delete(installedApp)
                
                do { try context.save() }
                catch { print("Failed to remove sideloaded app.", error) }
            }
        }))
        
        self.present(alertController, animated: true, completion: nil)
    }
}

private extension MyAppsViewController
{
    @objc func didFetchSource(_ notification: Notification)
    {
        DispatchQueue.main.async {
            if self.updatesDataSource.fetchedResultsController.fetchedObjects == nil
            {
                do { try self.updatesDataSource.fetchedResultsController.performFetch() }
                catch { print("Error fetching:", error) }
            }
            
            self.update()
        }
    }
    
    @objc func handleLongPressGesture(_ gestureRecognizer: UILongPressGestureRecognizer)
    {
        guard gestureRecognizer.state == .began else { return }
        
        let point = gestureRecognizer.location(in: self.collectionView)
        
        guard
            let indexPath = self.collectionView.indexPathForItem(at: point),
            indexPath.section == Section.installedApps.rawValue
        else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        #if DEBUG
        self.presentAlert(for: installedApp)
        #else
        if (UserDefaults.standard.legacySideloadedApps ?? []).contains(installedApp.bundleIdentifier)
        {
            // Only display alert for legacy sideloaded apps.
            self.presentAlert(for: installedApp)
        }
        #endif
    }
    
    @objc func importApp(_ notification: Notification)
    {
        // Make sure left UIBarButtonItem has been set.
        self.loadViewIfNeeded()
        
        guard let fileURL = notification.userInfo?[AppDelegate.importAppDeepLinkURLKey] as? URL else { return }
        guard self.presentedViewController == nil else { return }
        
        func finish()
        {
            do
            {
                try FileManager.default.removeItem(at: fileURL)
            }
            catch
            {
                print("Unable to remove imported .ipa.", error)
            }
        }
        
        #if BETA
        
        self.presentSideloadingAlert { (shouldContinue) in
            if shouldContinue
            {
                self.sideloadApp(at: fileURL) { (result) in
                    finish()
                }
            }
            else
            {
                finish()
            }
        }
        
        #else
        
        self.sideloadApp(at: fileURL) { (result) in
            finish()
        }
        
        #endif
    }
}

extension MyAppsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)!
        
        switch section
        {
        case .noUpdates: return UICollectionReusableView()
        case .updates:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader", for: indexPath) as! UpdatesCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.button.backgroundColor = UIColor.altPrimary.withAlphaComponent(0.15)
                headerView.button.setTitle("▾", for: .normal)
                headerView.button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
                headerView.button.setTitleColor(.altPrimary, for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.toggleAppUpdates), for: .primaryActionTriggered)
                
                if self.isUpdateSectionCollapsed
                {
                    headerView.button.titleLabel?.transform = .identity
                }
                else
                {
                    headerView.button.titleLabel?.transform = CGAffineTransform.identity.rotated(by: .pi)
                }
                
                headerView.isHidden = (self.updatesDataSource.itemCount <= 2)
                
                headerView.button.layoutIfNeeded()
            }
            
            return headerView
            
        case .installedApps where kind == UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "InstalledAppsHeader", for: indexPath) as! InstalledAppsCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.textLabel.text = NSLocalizedString("Installed", comment: "")
                
                headerView.button.isIndicatingActivity = false
                headerView.button.activityIndicatorView.color = .altPrimary
                headerView.button.setTitle(NSLocalizedString("Refresh All", comment: ""), for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.refreshAllApps(_:)), for: .primaryActionTriggered)
                headerView.button.isIndicatingActivity = self.isRefreshingAllApps
                
                headerView.button.layoutIfNeeded()
            }
            
            return headerView
            
        case .installedApps:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "InstalledAppsFooter", for: indexPath) as! InstalledAppsCollectionFooterView
            
            guard let team = DatabaseManager.shared.activeTeam() else { return footerView }
            switch team.type
            {
            case .free:
                let registeredAppIDs = team.appIDs.count
                
                let maximumAppIDCount = 10
                let remainingAppIDs = max(maximumAppIDCount - registeredAppIDs, 0)
                
                if remainingAppIDs == 1
                {
                    footerView.textLabel.text = String(format: NSLocalizedString("1 App ID Remaining", comment: ""))
                }
                else
                {
                    footerView.textLabel.text = String(format: NSLocalizedString("%@ App IDs Remaining", comment: ""), NSNumber(value: remainingAppIDs))
                }
                
                footerView.textLabel.isHidden = false
                
            case .individual, .organization, .unknown: footerView.textLabel.isHidden = true
            @unknown default: break
            }
            
            return footerView
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .updates:
            guard let cell = collectionView.cellForItem(at: indexPath) else { break }
            self.performSegue(withIdentifier: "showUpdate", sender: cell)
            
        default: break
        }
    }
}

extension MyAppsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .noUpdates:
            let size = CGSize(width: collectionView.bounds.width, height: 44)
            return size
            
        case .updates:
            let item = self.dataSource.item(at: indexPath)
            
            if let previousHeight = self.cachedUpdateSizes[item.bundleIdentifier]
            {
                return previousHeight
            }
            
            // Manually change cell's width to prevent conflicting with UIView-Encapsulated-Layout-Width constraints.
            self.prototypeUpdateCell.frame.size.width = collectionView.bounds.width
                        
            let widthConstraint = self.prototypeUpdateCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
            NSLayoutConstraint.activate([widthConstraint])
            defer { NSLayoutConstraint.deactivate([widthConstraint]) }
            
            self.dataSource.cellConfigurationHandler(self.prototypeUpdateCell, item, indexPath)
            
            let size = self.prototypeUpdateCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            self.cachedUpdateSizes[item.bundleIdentifier] = size
            return size

        case .installedApps:
            return CGSize(width: collectionView.bounds.width, height: 88)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates: return .zero
        case .updates:
            let height: CGFloat = self.updatesDataSource.itemCount > maximumCollapsedUpdatesCount ? 26 : 0
            return CGSize(width: collectionView.bounds.width, height: height)
            
        case .installedApps: return CGSize(width: collectionView.bounds.width, height: 29)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates: return .zero
        case .updates: return .zero
        case .installedApps:
            #if BETA
            guard let _ = DatabaseManager.shared.activeTeam() else { return .zero }
            
            let indexPath = IndexPath(row: 0, section: section.rawValue)
            let footerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionFooter, at: indexPath) as! InstalledAppsCollectionFooterView
                        
            let size = footerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
                                                          withHorizontalFittingPriority: .required,
                                                          verticalFittingPriority: .fittingSizeLevel)
            return size
            #else
            return .zero
            #endif
        }
    }
    
    func collectionView(_ myCV: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates where self.updatesDataSource.itemCount != 0: return .zero
        case .updates where self.updatesDataSource.itemCount == 0: return .zero
        default: return UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
        }
    }
}

extension MyAppsViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        // Responding to NSFetchedResultsController updates before the collection view has
        // been shown may throw exceptions because the collection view cannot accurately
        // count the number of items before the update. However, if we manually call
        // performBatchUpdates _before_ responding to updates, the collection view can get
        // an accurate pre-update item count.
        self.collectionView.performBatchUpdates(nil, completion: nil)
        
        self.updatesDataSource.controllerWillChangeContent(controller)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType)
    {
        self.updatesDataSource.controller(controller, didChange: sectionInfo, atSectionIndex: UInt(sectionIndex), for: type)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)
    {
        self.updatesDataSource.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        let previousUpdateCount = self.collectionView.numberOfItems(inSection: Section.updates.rawValue)
        let updateCount = Int(self.updatesDataSource.itemCount)
        
        if previousUpdateCount == 0 && updateCount > 0
        {
            // Remove "No Updates Available" cell.
            let change = RSTCellContentChange(type: .delete, currentIndexPath: IndexPath(item: 0, section: Section.noUpdates.rawValue), destinationIndexPath: nil)
            self.collectionView.add(change)
        }
        else if previousUpdateCount > 0 && updateCount == 0
        {
            // Insert "No Updates Available" cell.
            let change = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: IndexPath(item: 0, section: Section.noUpdates.rawValue))
            self.collectionView.add(change)
        }
        
        self.updatesDataSource.controllerDidChangeContent(controller)
    }
}

extension MyAppsViewController: UIDocumentPickerDelegate
{
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    {
        guard let fileURL = urls.first else { return }
        
        self.sideloadApp(at: fileURL) { (result) in
            print("Sideloaded app at \(fileURL) with result:", result)
        }
    }
}

extension MyAppsViewController: UIViewControllerPreviewingDelegate
{
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        guard
            let indexPath = self.collectionView.indexPathForItem(at: location),
            let cell = self.collectionView.cellForItem(at: indexPath)
        else { return nil }
        
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .updates:
            previewingContext.sourceRect = cell.frame
            
            let app = self.dataSource.item(at: indexPath)
            guard let storeApp = app.storeApp else { return nil}
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
            
        default: return nil
        }
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        let point = CGPoint(x: previewingContext.sourceRect.midX, y: previewingContext.sourceRect.midY)
        guard let indexPath = self.collectionView.indexPathForItem(at: point), let cell = self.collectionView.cellForItem(at: indexPath) else { return }
        
        self.performSegue(withIdentifier: "showUpdate", sender: cell)
    }
}
