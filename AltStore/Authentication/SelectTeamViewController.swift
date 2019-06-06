//
//  SelectTeamViewController.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltSign
import Roxas

class SelectTeamViewController: UITableViewController
{
    var selectionHandler: ((ALTTeam?) -> Void)?
    
    var teams: [ALTTeam] {
        get {
            return self.dataSource.items
        }
        set {
            self.dataSource.items = newValue
        }
    }
    
    private var selectedTeam: ALTTeam? {
        didSet {
            self.update()
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        
        self.update()
    }
    
    override func viewWillDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        self.navigationItem.rightBarButtonItem?.isIndicatingActivity = false
    }
}

private extension SelectTeamViewController
{
    func makeDataSource() -> RSTArrayTableViewDataSource<ALTTeam>
    {
        let dataSource = RSTArrayTableViewDataSource<ALTTeam>(items: [])
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, team, indexPath) in
            cell.textLabel?.text = team.name
            
            switch team.type
            {
            case .unknown: cell.detailTextLabel?.text = NSLocalizedString("Unknown", comment: "")
            case .free: cell.detailTextLabel?.text = NSLocalizedString("Free Developer Account", comment: "")
            case .individual: cell.detailTextLabel?.text = NSLocalizedString("Individual", comment: "")
            case .organization: cell.detailTextLabel?.text = NSLocalizedString("Organization", comment: "")
            @unknown default: cell.detailTextLabel?.text = nil
            }
            
            cell.accessoryType = (self?.selectedTeam == team) ? .checkmark : .none
        }
        
        let placeholderView = RSTPlaceholderView(frame: .zero)
        placeholderView.textLabel.text = NSLocalizedString("No Teams", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("You are not a member of any development teams.", comment: "")
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
    
    func update()
    {
        self.navigationItem.rightBarButtonItem?.isEnabled = (self.selectedTeam != nil)
        
        if self.isViewLoaded
        {
            self.tableView.reloadData()
        }
    }
    
    func fetchCertificates(for team: ALTTeam, completionHandler: @escaping (Result<[ALTCertificate], Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchCertificates(for: team) { (certificate, error) in
            let result = Result(certificate, error)
            completionHandler(result)
        }
    }
}

private extension SelectTeamViewController
{
    @IBAction func chooseTeam(_ sender: UIBarButtonItem)
    {
        guard let team = self.selectedTeam else { return }
        
        func choose()
        {
            sender.isIndicatingActivity = true
            
            self.selectionHandler?(team)
        }
        
        if team.type == .organization
        {
            let localizedActionTitle = String(format: NSLocalizedString("Use %@?", comment: ""), team.name)
            
            let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to use an Organization team?", comment: ""),
                                                    message: NSLocalizedString("Doing so may affect other members of this team.", comment: ""), preferredStyle: .actionSheet)
            alertController.addAction(UIAlertAction(title: localizedActionTitle, style: .destructive, handler: { (action) in
                choose()
            }))
            alertController.addAction(.cancel)
            
            self.present(alertController, animated: true, completion: nil)
        }
        else
        {
            choose()
        }
    }
    
    @IBAction func cancel()
    {
        self.selectionHandler?(nil)
    }
}

extension SelectTeamViewController
{
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    {
        return NSLocalizedString("Select the team you would like to use to install apps.", comment: "")
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let team = self.dataSource.item(at: indexPath)
        self.selectedTeam = team
    }
}
