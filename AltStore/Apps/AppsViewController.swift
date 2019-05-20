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
    
    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter
    }()
    
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
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let appsFileURL = Bundle.main.url(forResource: "Apps", withExtension: "json")!
            
            do
            {
                let data = try Data(contentsOf: appsFileURL)
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .formatted(self.dateFormatter)
                decoder.managedObjectContext = context
                
                _ = try decoder.decode([App].self, from: data)
                try context.save()
            }
            catch
            {
                fatalError("Failed to save fetched apps. \(error)")
            }
        }
    }
}
