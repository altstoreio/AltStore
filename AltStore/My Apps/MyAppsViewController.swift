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

private extension Date
{
    func numberOfCalendarDays(since date: Date) -> Int
    {
        let today = Calendar.current.startOfDay(for: self)
        let previousDay = Calendar.current.startOfDay(for: date)
        
        let components = Calendar.current.dateComponents([.day], from: previousDay, to: today)
        return components.day!
    }
}

class MyAppsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    private lazy var noUpdatesDataSource = self.makeNoUpdatesDataSource()
    private lazy var updatesDataSource = self.makeUpdatesDataSource()
    private lazy var installedAppsDataSource = self.makeInstalledAppsDataSource()
    
    private var prototypeUpdateCell: UpdateCollectionViewCell!
    
    // State
    private var isUpdateSectionCollapsed = true
    private var expandedAppUpdates = Set<String>()
    private var isRefreshingAllApps = false
    private var refreshGroup: OperationGroup?
    
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.didFetchApps(_:)), name: AppManager.didFetchAppsNotification, object: nil)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Allows us to intercept delegate callbacks.
        self.updatesDataSource.fetchedResultsController.delegate = self
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
                
        self.prototypeUpdateCell = UpdateCollectionViewCell.instantiate(with: UpdateCollectionViewCell.nib!)
        self.prototypeUpdateCell.translatesAutoresizingMaskIntoConstraints = false
        self.prototypeUpdateCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(UpdateCollectionViewCell.nib, forCellWithReuseIdentifier: "UpdateCell")
        self.collectionView.register(UpdatesCollectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader")
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "showApp" else { return }
        
        guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let appViewController = segue.destination as! AppViewController
        appViewController.app = installedApp.app
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
            cell.layer.cornerRadius = 20
            cell.layer.masksToBounds = true
            cell.contentView.backgroundColor = UIColor.altGreen.withAlphaComponent(0.15)
        }
        
        return dynamicDataSource
    }
    
    func makeUpdatesDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.updatesFetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.app?.versionDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.app?.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.liveFetchLimit = maximumCollapsedUpdatesCount
        dataSource.cellIdentifierHandler = { _ in "UpdateCell" }
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            let cell = cell as! UpdateCollectionViewCell
            cell.tintColor = app.tintColor ?? .altGreen
            cell.nameLabel.text = app.name
            cell.versionDescriptionTextView.text = app.versionDescription
            cell.appIconImageView.image = UIImage(named: app.iconName)
            
            cell.updateButton.isIndicatingActivity = false
            cell.updateButton.addTarget(self, action: #selector(MyAppsViewController.updateApp(_:)), for: .primaryActionTriggered)
            
            if self.expandedAppUpdates.contains(app.identifier)
            {
                cell.mode = .expanded
            }
            else
            {
                cell.mode = .collapsed
            }
            
            cell.versionDescriptionTextView.moreButton.addTarget(self, action: #selector(MyAppsViewController.toggleUpdateCellMode(_:)), for: .primaryActionTriggered)
            
            let progress = AppManager.shared.installationProgress(for: app)
            cell.updateButton.progress = progress
            
            cell.dateLabel.text = self.dateFormatter.string(from: app.versionDate)
            
            let numberOfDays = Date().numberOfCalendarDays(since: app.versionDate)
            switch numberOfDays
            {
            case 0: cell.dateLabel.text = NSLocalizedString("Today", comment: "")
            case 1: cell.dateLabel.text = NSLocalizedString("Yesterday", comment: "")
            case 2...7: cell.dateLabel.text = String(format: NSLocalizedString("%@ days ago", comment: ""), NSNumber(value: numberOfDays))
            default: cell.dateLabel.text = self.dateFormatter.string(from: app.versionDate)
            }
            
            cell.setNeedsLayout()
        }
        
        return dataSource
    }
    
    func makeInstalledAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.refreshedDate, ascending: false),
                                        NSSortDescriptor(keyPath: \InstalledApp.app?.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            let tintColor = app.tintColor ?? .altGreen
            
            let cell = cell as! InstalledAppCollectionViewCell
            cell.tintColor = tintColor
            cell.appIconImageView.image = UIImage(named: app.iconName)
            cell.refreshButton.isIndicatingActivity = false
            cell.refreshButton.addTarget(self, action: #selector(MyAppsViewController.refreshApp(_:)), for: .primaryActionTriggered)
            
            let currentDate = Date()
            
            let numberOfDays = installedApp.expirationDate.numberOfCalendarDays(since: currentDate)
            
            if numberOfDays == 1
            {
                cell.refreshButton.setTitle(NSLocalizedString("1 DAY", comment: ""), for: .normal)
            }
            else
            {
                cell.refreshButton.setTitle(String(format: NSLocalizedString("%@ DAYS", comment: ""), NSNumber(value: numberOfDays)), for: .normal)
            }
                                    
            cell.nameLabel.text = app.name
            cell.developerLabel.text = app.developerName
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
            
            switch numberOfDays
            {
            case 2...3: cell.refreshButton.tintColor = .refreshOrange
            case 4...5: cell.refreshButton.tintColor = .refreshYellow
            case 6...: cell.refreshButton.tintColor = .refreshGreen
            default: cell.refreshButton.tintColor = .refreshRed
            }
            
            if let refreshGroup = self.refreshGroup, let progress = refreshGroup.progress(for: app), progress.fractionCompleted < 1.0
            {
                cell.refreshButton.progress = progress
            }
            else
            {
                cell.refreshButton.progress = nil
            }
        }
        
        return dataSource
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
        
        UIView.performWithoutAnimation {
            self.collectionView.reloadSections(IndexSet(integer: Section.updates.rawValue))
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
                        let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                        toastView.setNeedsLayout()
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                        
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
                        
                        let localizedText: String
                        if let failure = failures.first, failures.count == 1
                        {
                            localizedText = failure.value.localizedDescription
                        }
                        else
                        {
                            localizedText = String(format: NSLocalizedString("Failed to refresh %@ apps.", comment: ""), NSNumber(value: failures.count))
                        }
                        
                        let toastView = ToastView(text: localizedText, detailText: nil)
                        toastView.tintColor = .refreshRed
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
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
        
        if installedApps.contains(where: { $0.app.identifier == App.altstoreAppID })
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
        
        if self.expandedAppUpdates.contains(installedApp.app.identifier)
        {
            self.expandedAppUpdates.remove(installedApp.app.identifier)
            cell?.mode = .collapsed
        }
        else
        {
            self.expandedAppUpdates.insert(installedApp.app.identifier)
            cell?.mode = .expanded
        }
        
        self.cachedUpdateSizes[installedApp.app.identifier] = nil
        
        self.collectionView.performBatchUpdates({
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }
    
    @IBAction func refreshApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let previousProgress = AppManager.shared.refreshProgress(for: installedApp.app)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        self.refresh([installedApp]) { (result) in
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
        
        let app = self.dataSource.item(at: indexPath).app!
        
        let previousProgress = AppManager.shared.installationProgress(for: app)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        _ = AppManager.shared.install(app, presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled):
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .failure(let error):
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                    
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .success:
                    print("Updated app:", app.identifier)
                    // No need to reload, since the the update cell is gone now.
                }
                
                self.update()
            }
        }
        
        self.collectionView.reloadItems(at: [indexPath])
    }
    
    @objc func didFetchApps(_ notification: Notification)
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
}

extension MyAppsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        if indexPath.section == 0
        {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader", for: indexPath) as! UpdatesCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.button.backgroundColor = UIColor.altGreen.withAlphaComponent(0.15)
                headerView.button.setTitle("▾", for: .normal)
                headerView.button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
                headerView.button.setTitleColor(.altGreen, for: .normal)
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
        }
        else
        {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "InstalledAppsHeader", for: indexPath) as! InstalledAppsCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.textLabel.text = NSLocalizedString("Installed", comment: "")
                
                headerView.button.isIndicatingActivity = false
                headerView.button.activityIndicatorView.color = .altGreen
                headerView.button.setTitle(NSLocalizedString("Refresh All", comment: ""), for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.refreshAllApps(_:)), for: .primaryActionTriggered)
                headerView.button.isIndicatingActivity = self.isRefreshingAllApps
                
                headerView.button.layoutIfNeeded()
            }
            
            return headerView
        }
    }
}

extension MyAppsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let padding = 30 as CGFloat
        let width = collectionView.bounds.width - padding
        
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .noUpdates:
            let size = CGSize(width: width, height: 44)
            return size
            
        case .updates:
            let item = self.dataSource.item(at: indexPath)
            
            if let previousHeight = self.cachedUpdateSizes[item.app!.identifier]
            {
                return previousHeight
            }
            
            let widthConstraint = self.prototypeUpdateCell.contentView.widthAnchor.constraint(equalToConstant: width)
            NSLayoutConstraint.activate([widthConstraint])
            defer { NSLayoutConstraint.deactivate([widthConstraint]) }
            
            self.dataSource.cellConfigurationHandler(self.prototypeUpdateCell, item, indexPath)
            
            let size = self.prototypeUpdateCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            self.cachedUpdateSizes[item.app!.identifier] = size
            return size

        case .installedApps:
            return CGSize(width: collectionView.bounds.width, height: 60)
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
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates:
            guard self.updatesDataSource.itemCount == 0 else { return .zero }
            return UIEdgeInsets(top: 12, left: 15, bottom: 20, right: 15)
            
        case .updates:
            guard self.updatesDataSource.itemCount > 0 else { return .zero }
            return UIEdgeInsets(top: 12, left: 15, bottom: 20, right: 15)
            
        case .installedApps: return UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
        }
    }
}

extension MyAppsViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
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
