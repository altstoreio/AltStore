//
//  PatreonViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AuthenticationServices

import Roxas

class PatreonViewController: UITableViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    @IBOutlet private var signInButton: UIBarButtonItem!
    @IBOutlet private var signOutButton: UIBarButtonItem!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.tableView.dataSource = self.dataSource
        
        self.update()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchPatrons()
    }
}

private extension PatreonViewController
{
    func makeDataSource() -> RSTArrayTableViewDataSource<Patron>
    {
        let dataSource = RSTArrayTableViewDataSource<Patron>(items: [])
        dataSource.cellConfigurationHandler = { (cell, patron, indexPath) in
            cell.textLabel?.text = patron.name
        }
        
        return dataSource
    }
    
    func update()
    {
        if PatreonAPI.shared.isAuthenticated && DatabaseManager.shared.patreonAccount() != nil
        {
            self.navigationItem.rightBarButtonItem = self.signOutButton
        }
        else
        {
            self.navigationItem.rightBarButtonItem = self.signInButton
        }
    }
    
    func fetchPatrons()
    {
        PatreonAPI.shared.fetchPatrons { (result) in
            do
            {
                let patrons = try result.get()
                self.dataSource.items = patrons
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                }
            }
        }
    }
}

private extension PatreonViewController
{
    @IBAction func authenticate(_ sender: UIBarButtonItem)
    {
        PatreonAPI.shared.authenticate { (result) in
            do
            {
                let account = try result.get()
                try account.managedObjectContext?.save()
                
                DispatchQueue.main.async {
                    self.update()
                }
            }
            catch ASWebAuthenticationSessionError.canceledLogin
            {
                // Ignore
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                }
            }
        }
    }
    
    @IBAction func signOut(_ sender: UIBarButtonItem)
    {
        PatreonAPI.shared.signOut { (result) in
            do
            {
                try result.get()
                
                DispatchQueue.main.async {
                    self.update()
                }
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(text: error.localizedDescription, detailText: nil)
                    toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                }
            }
        }
    }
}
