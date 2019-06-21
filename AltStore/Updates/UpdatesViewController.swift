//
//  UpdatesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class UpdatesViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    @IBOutlet private var progressView: UIProgressView!
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(UpdatesViewController.didFetchApps(_:)), name: AppManager.didFetchAppsNotification, object: nil)
    }
    
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
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
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

private extension UpdatesViewController
{
    func makeDataSource() -> RSTFetchedResultsTableViewDataSource<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K != %K", #keyPath(InstalledApp.version), #keyPath(InstalledApp.app.version))
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.app?.versionDate, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsTableViewDataSource(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            cell.textLabel?.text = app.name + " (\(app.version))"
            
            let detailText = self.dateFormatter.string(from: app.versionDate) + "\n\n" + (app.versionDescription ?? "No Update Description")
            
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.text = detailText
        }
        
        let placeholderView = RSTPlaceholderView()
        placeholderView.textLabel.text = NSLocalizedString("No Updates", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("There are no app updates at this time.", comment: "")
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
    
    func update()
    {
        if let count = self.dataSource.fetchedResultsController.fetchedObjects?.count, count > 0
        {
            self.navigationController?.tabBarItem.badgeValue = String(describing: count)
        }
        else
        {
            self.navigationController?.tabBarItem.badgeValue = nil
        }
    }
}

private extension UpdatesViewController
{
    func update(_ installedApp: InstalledApp)
    {
        func updateApp()
        {
            let toastView = RSTToastView(text: "Updating...", detailText: nil)
            toastView.tintColor = .altPurple
            toastView.activityIndicatorView.startAnimating()
            toastView.show(in: self.navigationController?.view ?? self.view)
            
            let progress = AppManager.shared.install(installedApp.app, presentingViewController: self) { (result) in
                do
                {
                    _ = try result.get()
                    
                    DispatchQueue.main.async {
                        let installedApp = DatabaseManager.shared.persistentContainer.viewContext.object(with: installedApp.objectID) as! InstalledApp
                        
                        let toastView = RSTToastView(text: "Updated \(installedApp.app.name) to version \(installedApp.version)!", detailText: nil)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                        
                        self.update()
                    }
                }
                catch
                {
                    DispatchQueue.main.async {
                        let toastView = RSTToastView(text: "Failed to update \(installedApp.app.name)", detailText: error.localizedDescription)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                    }
                }
                
                DispatchQueue.main.async {
                    self.progressView.observedProgress = nil
                    self.progressView.progress = 0.0
                }
            }
            
            self.progressView.observedProgress = progress
        }
        
        if installedApp.app.identifier == App.altstoreAppID
        {
            let alertController = UIAlertController(title: NSLocalizedString("Update AltStore?", comment: ""), message: NSLocalizedString("AltStore will quit upon completion.", comment: ""), preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Update and Quit", comment: ""), style: .default, handler: { (action) in
                updateApp()
            }))
            alertController.addAction(.cancel)
            
            self.present(alertController, animated: true, completion: nil)
        }
        else
        {
            updateApp()
        }
    }
    
    @objc func didFetchApps(_ notification: Notification)
    {
        DispatchQueue.main.async {
            if self.dataSource.fetchedResultsController.fetchedObjects == nil
            {
                do { try self.dataSource.fetchedResultsController.performFetch() }
                catch { print("Error fetching:", error) }
            }
            
            self.update()
        }
    }
}

extension UpdatesViewController
{
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]?
    {
        let updateAction = UITableViewRowAction(style: .normal, title: "Update") { [weak self] (action, indexPath) in
            guard let installedApp = self?.dataSource.item(at: indexPath) else { return }
            self?.update(installedApp)
        }
        updateAction.backgroundColor = .altPurple
        
        return [updateAction]
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    {
    }
}
