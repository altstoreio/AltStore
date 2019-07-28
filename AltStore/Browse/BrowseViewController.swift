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
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchApps()
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        let collectionViewLayout = self.collectionViewLayout as! UICollectionViewFlowLayout
        collectionViewLayout.itemSize.width = self.view.bounds.width
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
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \App.name, ascending: false)]
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(App.bundleIdentifier), App.altstoreAppID)
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<App, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
            let cell = cell as! BrowseCollectionViewCell
            cell.nameLabel.text = app.name
            cell.developerLabel.text = app.developerName
            cell.subtitleLabel.text = app.subtitle
            cell.imageNames = Array(app.screenshotNames.prefix(3))
            cell.appIconImageView.image = UIImage(named: app.iconName)
            
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
    
    func fetchApps()
    {
        AppManager.shared.fetchApps() { (result) in
            do
            {                
                let apps = try result.get()
                try apps.first?.managedObjectContext?.save()
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
