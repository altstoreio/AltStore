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
    func makeDataSource() -> RSTArrayTableViewDataSource<App>
    {
        let appsFileURL = Bundle.main.url(forResource: "Apps", withExtension: "plist")!
        
        do
        {
            let data = try Data(contentsOf: appsFileURL)
            let apps = try PropertyListDecoder().decode([App].self, from: data)
            
            let dataSource = RSTArrayTableViewDataSource(items: apps)
            dataSource.cellConfigurationHandler = { (cell, app, indexPath) in
                let cell = cell as! AppTableViewCell
                cell.nameLabel.text = app.name
                cell.subtitleLabel.text = app.subtitle
                cell.appIconImageView.image = UIImage(named: app.iconName)
            }
            return dataSource
        }
        catch
        {
            fatalError("Failed to load apps. \(error)")
        }
    }
}
