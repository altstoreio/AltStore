//
//  RefreshAttemptsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

@objc(RefreshAttemptTableViewCell)
private class RefreshAttemptTableViewCell: UITableViewCell
{
    @IBOutlet var successLabel: UILabel!
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var errorDescriptionLabel: UILabel!
}

class RefreshAttemptsViewController: UITableViewController
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
}

private extension RefreshAttemptsViewController
{
    func makeDataSource() -> RSTFetchedResultsTableViewDataSource<RefreshAttempt>
    {
        let fetchRequest = RefreshAttempt.fetchRequest() as NSFetchRequest<RefreshAttempt>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \RefreshAttempt.date, ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsTableViewDataSource(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { [weak self] (cell, attempt, indexPath) in
            let cell = cell as! RefreshAttemptTableViewCell
            cell.dateLabel.text = self?.dateFormatter.string(from: attempt.date)
            cell.errorDescriptionLabel.text = attempt.errorDescription
            
            if attempt.isSuccess
            {
                cell.successLabel.text = NSLocalizedString("Success", comment: "")
                cell.successLabel.textColor = .refreshGreen
            }
            else
            {
                cell.successLabel.text = NSLocalizedString("Failure", comment: "")
                cell.successLabel.textColor = .refreshRed
            }
        }
        
        let placeholderView = RSTPlaceholderView()
        placeholderView.textLabel.text = NSLocalizedString("No Refresh Attempts", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("The more you use AltStore, the more often iOS will allow it to refresh apps in the background.", comment: "")
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
}
