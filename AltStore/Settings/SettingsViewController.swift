//
//  AccountViewController.swift
//  AltStore
//
//  Created by Riley Testut on 6/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class SettingsViewController: UITableViewController
{
    private var team: Team?
    
    private lazy var placeholderView = self.makePlaceholderView()
    
    @IBOutlet var accountNameLabel: UILabel!
    @IBOutlet var accountEmailLabel: UILabel!
    
    @IBOutlet var teamNameLabel: UILabel!
    @IBOutlet var teamTypeLabel: UILabel!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.update()
    }
}

private extension SettingsViewController
{
    func makePlaceholderView() -> RSTPlaceholderView
    {
        let placeholderView = RSTPlaceholderView()
        placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        placeholderView.textLabel.text = NSLocalizedString("Not Signed In", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("Please sign in with your Apple ID to download and refresh apps.", comment: "")
        
        let signInButton = UIButton(type: .system)
        signInButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        signInButton.setTitle(NSLocalizedString("Sign In", comment: ""), for: .normal)
        signInButton.addTarget(self, action: #selector(SettingsViewController.signIn(_:)), for: .primaryActionTriggered)
        placeholderView.stackView.addArrangedSubview(signInButton)
        
        return placeholderView
    }
    
    func update()
    {
        if let team = DatabaseManager.shared.activeTeam()
        {
            self.tableView.separatorStyle = .singleLine
            self.tableView.isScrollEnabled = true
            self.tableView.backgroundView = nil
            
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            
            self.accountNameLabel.text = team.account.localizedName
            self.accountEmailLabel.text = team.account.appleID
            
            self.teamNameLabel.text = team.name
            self.teamTypeLabel.text = team.type.localizedDescription
            
            self.team = team
        }
        else
        {
            self.tableView.separatorStyle = .none
            self.tableView.isScrollEnabled = false
            self.tableView.backgroundView = self.placeholderView
            
            self.navigationItem.rightBarButtonItem?.isEnabled = false
            
            self.team = nil
        }
        
        if self.isViewLoaded
        {
            self.tableView.reloadData()
        }
    }
}

private extension SettingsViewController
{
    @objc func signIn(_ sender: UIButton)
    {
        sender.isIndicatingActivity = true
        
        AppManager.shared.authenticate(presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                sender.isIndicatingActivity = false
                self.update()
            }
        }
    }
    
    @IBAction func signOut(_ sender: UIBarButtonItem)
    {
        func signOut()
        {
            DatabaseManager.shared.signOut { (error) in
                DispatchQueue.main.async {
                    if let error = error
                    {
                        let toastView = RSTToastView(text: error.localizedDescription, detailText: nil)
                        toastView.tintColor = .red
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    }
                    else
                    {
                        let toastView = RSTToastView(text: NSLocalizedString("Successfully Signed Out!", comment: ""), detailText: nil)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                    }
                    
                    self.update()
                }
            }
        }
        
        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to sign out?", comment: ""), message: NSLocalizedString("You will no longer be able to install or refresh apps once you sign out.", comment: ""), preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Sign Out", comment: ""), style: .destructive) { _ in signOut() })
        alertController.addAction(.cancel)
        self.present(alertController, animated: true, completion: nil)
    }
}

extension SettingsViewController
{
    override func numberOfSections(in tableView: UITableView) -> Int
    {
        let count = (self.team == nil) ? 0 : super.numberOfSections(in: tableView)
        return count
    }
}


