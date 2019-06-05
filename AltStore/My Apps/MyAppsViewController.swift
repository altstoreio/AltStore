//
//  MyAppsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

class MyAppsViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
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
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            cell.textLabel?.text = app.name
            
            let detailText =
            """
            Expires: \(self.dateFormatter.string(from: installedApp.expirationDate))
            """
            
            cell.detailTextLabel?.numberOfLines = 1
            cell.detailTextLabel?.text = detailText
            cell.detailTextLabel?.textColor = .red
        }
        
        return dataSource
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
            
            let toastView = RSTToastView(text: "Refreshing...", detailText: nil)
            toastView.tintColor = .altPurple
            toastView.activityIndicatorView.startAnimating()
            toastView.show(in: self.navigationController?.view ?? self.view)
            
            AppManager.shared.refresh(installedApp) { (result) in
                do
                {
                    let app = try result.get()
                    try app.managedObjectContext?.save()
                    
                    DispatchQueue.main.async {
                        let toastView = RSTToastView(text: "Refreshed \(installedApp.app.name)!", detailText: nil)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                    }
                }
                catch
                {
                    DispatchQueue.main.async {
                        let toastView = RSTToastView(text: "Failed to refresh \(installedApp.app.name)", detailText: error.localizedDescription)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2)
                    }
                }
            }
        }
        
        return [deleteAction, refreshAction]
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    {
    }
}
