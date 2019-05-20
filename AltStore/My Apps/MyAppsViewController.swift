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
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
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
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            guard let app = installedApp.app else { return }
            
            cell.textLabel?.text = app.name
            
            let detailText =
            """
            Signed: \(self.dateFormatter.string(from: installedApp.signedDate))
            Expires: \(self.dateFormatter.string(from: installedApp.expirationDate))
            """
            
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.text = detailText
        }
        
        return dataSource
    }
}
