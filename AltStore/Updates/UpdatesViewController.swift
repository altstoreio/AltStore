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
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        let count = self.tableView.numberOfRows(inSection: 0)
        self.navigationController?.tabBarItem.badgeValue = count > 0 ? String(describing: count) : nil
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
        
        return dataSource
    }
}
