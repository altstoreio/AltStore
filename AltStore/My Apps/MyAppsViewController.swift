//
//  MyAppsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

import AltSign

class MyAppsViewController: UITableViewController
{
    private var refreshErrors = [String: Error]()
    
    private lazy var dataSource = self.makeDataSource()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()
    
    private var refreshGroup: OperationGroup?
    
    @IBOutlet private var progressView: UIProgressView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            self.progressView.translatesAutoresizingMaskIntoConstraints = false
            navigationBar.addSubview(self.progressView)
            
            NSLayoutConstraint.activate([self.progressView.widthAnchor.constraint(equalTo: navigationBar.widthAnchor),
                                         self.progressView.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor)])
        }
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.update()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "showAppDetail" else { return }
        
        guard let cell = sender as? UITableViewCell, let indexPath = self.tableView.indexPath(for: cell) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        guard let app = installedApp.app else { return }
        
        let appDetailViewController = segue.destination as! AppDetailViewController
        appDetailViewController.app = app
    }
}

private extension MyAppsViewController
{
    func makeDataSource() -> RSTFetchedResultsTableViewDataSource<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.app?.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsTableViewDataSource(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            cell.textLabel?.text = app.name + " (\(installedApp.version))"
            
            let detailText =
            """
            Expires: \(self?.dateFormatter.string(from: installedApp.expirationDate) ?? "-")
            """
            
            cell.detailTextLabel?.numberOfLines = 1
            cell.detailTextLabel?.text = detailText
            cell.detailTextLabel?.textColor = .red
            
            if let _ = self?.refreshErrors[installedApp.bundleIdentifier]
            {
                cell.accessoryType = .detailButton
                cell.tintColor = .red
            }
            else
            {
                cell.accessoryType = .none
                cell.tintColor = nil
            }
        }
        
        return dataSource
    }
    
    func update()
    {
        self.navigationItem.rightBarButtonItem?.isEnabled = !(self.dataSource.fetchedResultsController.fetchedObjects?.isEmpty ?? true)
        
        self.tableView.reloadData()
    }
}

private extension MyAppsViewController
{
    @IBAction func refreshAllApps(_ sender: UIBarButtonItem)
    {
        sender.isIndicatingActivity = true
        
        let installedApps = InstalledApp.fetchAppsForRefreshingAll(in: DatabaseManager.shared.viewContext)
        
        self.refresh(installedApps) { (result) in
            sender.isIndicatingActivity = false
        }
    }
    
    func refresh(_ installedApps: [InstalledApp], completionHandler: @escaping (Result<[String : Result<InstalledApp, Error>], Error>) -> Void)
    {
        if self.refreshGroup == nil
        {
            let toastView = RSTToastView(text: "Refreshing...", detailText: nil)
            toastView.tintColor = .altPurple
            toastView.activityIndicatorView.startAnimating()
            toastView.show(in: self.navigationController?.view ?? self.view)
        }
        
        let group = AppManager.shared.refresh(installedApps, presentingViewController: self, group: self.refreshGroup)
        group.completionHandler = { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(let error):
                    let toastView = RSTToastView(text: error.localizedDescription, detailText: nil)
                    toastView.tintColor = .red
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    
                    self.refreshErrors = [:]
                    
                case .success(let results):
                    let failures = results.compactMapValues { $0.error }
                    
                    if failures.isEmpty
                    {
                        let toastView = RSTToastView(text: NSLocalizedString("Successfully refreshed apps!", comment: ""), detailText: nil)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    }
                    else
                    {
                        let localizedText: String
                        if failures.count == 1
                        {
                            localizedText = String(format: NSLocalizedString("Failed to refresh %@ app.", comment: ""), NSNumber(value: failures.count))
                        }
                        else
                        {
                            localizedText = String(format: NSLocalizedString("Failed to refresh %@ apps.", comment: ""), NSNumber(value: failures.count))
                        }
                        
                        let toastView = RSTToastView(text: localizedText, detailText: nil)
                        toastView.tintColor = .red
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    }
                    
                    self.refreshErrors = failures
                }
                
                self.progressView.observedProgress = nil
                self.progressView.progress = 0.0
                
                self.update()
                
                self.refreshGroup = nil
                completionHandler(result)
            }
        }
        
        self.progressView.observedProgress = group.progress
        
        self.refreshGroup = group
    }
}

extension MyAppsViewController
{
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]?
    {
        let deleteAction = UITableViewRowAction(style: .destructive, title: "Delete") { (action, indexPath) in
            let installedApp = self.dataSource.item(at: indexPath)
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                context.delete(installedApp)
                
                do
                {
                    try context.save()
                }
                catch
                {
                    print("Failed to delete installed app.", error)
                }
            }
        }
        
        let refreshAction = UITableViewRowAction(style: .normal, title: "Refresh") { (action, indexPath) in
            let installedApp = self.dataSource.item(at: indexPath)
            self.refresh([installedApp]) { (result) in
                print("Refreshed", installedApp.app.identifier)
            }
        }
        
        return [deleteAction, refreshAction]
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    {
    }
    
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath)
    {
        let installedApp = self.dataSource.item(at: indexPath)
        
        guard let error = self.refreshErrors[installedApp.bundleIdentifier] else { return }
        
        let alertController = UIAlertController(title: "Failed to Refresh \(installedApp.app.name)", message: error.localizedDescription, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
}
