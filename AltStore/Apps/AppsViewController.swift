//
//  AppsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

class AppsViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()    
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        
        // Hide trailing row separators.
        self.tableView.tableFooterView = UIView()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchApps()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard segue.identifier == "showAppDetail" else { return }
        
        guard let cell = sender as? UITableViewCell, let indexPath = self.tableView.indexPath(for: cell) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        
        let appDetailViewController = segue.destination as! AppDetailViewController
        appDetailViewController.app = app
    }
}

private extension AppsViewController
{
    func makeDataSource() -> RSTFetchedResultsTableViewDataSource<App>
    {
        let fetchRequest = App.fetchRequest() as NSFetchRequest<App>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \App.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsTableViewDataSource(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
            let cell = cell as! AppTableViewCell
            cell.nameLabel.text = app.name
            cell.developerLabel.text = app.developerName
            cell.appIconImageView.image = UIImage(named: app.iconName)
            
            if app.installedApp != nil
            {
                cell.button.isEnabled = false
                cell.button.setTitle(NSLocalizedString("Installed", comment: ""), for: .normal)
            }
            else
            {
                cell.button.isEnabled = true
                cell.button.setTitle(NSLocalizedString("Download", comment: ""), for: .normal)
            }
        }
        
        return dataSource
    }
    
    func fetchApps()
    {
        AppManager.shared.fetchApps { (result) in
            do
            {
                let apps = try result.get()
                try apps.first?.managedObjectContext?.save()
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = RSTToastView(text: NSLocalizedString("Failed to fetch apps", comment: ""), detailText: error.localizedDescription)
                    toastView.tintColor = .altPurple
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                }
            }
        }
    }
}
