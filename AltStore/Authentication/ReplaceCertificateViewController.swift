//
//  ReplaceCertificateViewController.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltSign
import Roxas

extension ReplaceCertificateViewController
{
    private enum Error: LocalizedError
    {
        case missingPrivateKey
        case missingCertificate
        
        var errorDescription: String? {
            switch self
            {
            case .missingPrivateKey: return NSLocalizedString("The certificate's private key could not be found.", comment: "")
            case .missingCertificate: return NSLocalizedString("The certificate could not be found.", comment: "")
            }
        }
    }
}

class ReplaceCertificateViewController: UITableViewController
{
    var replacementHandler: ((ALTCertificate?) -> Void)?
    
    var team: ALTTeam!
    
    var certificates: [ALTCertificate] {
        get {
            return self.dataSource.items
        }
        set {
            self.dataSource.items = newValue
        }
    }
    
    private var selectedCertificate: ALTCertificate? {
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
}

private extension ReplaceCertificateViewController
{
    func makeDataSource() -> RSTArrayTableViewDataSource<ALTCertificate>
    {
        let dataSource = RSTArrayTableViewDataSource<ALTCertificate>(items: [])
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, certificate, indexPath) in
            cell.textLabel?.text = certificate.name
            cell.accessoryType = (self?.selectedCertificate == certificate) ? .checkmark : .none
        }
        
        let placeholderView = RSTPlaceholderView(frame: .zero)
        placeholderView.textLabel.text = NSLocalizedString("No Certificates", comment: "")
        placeholderView.detailTextLabel.text = NSLocalizedString("There are no certificates associated with this team.", comment: "")
        dataSource.placeholderView = placeholderView
        
        return dataSource
    }
    
    func update()
    {
        self.navigationItem.rightBarButtonItem?.isEnabled = (self.selectedCertificate != nil)
        
        if self.isViewLoaded
        {
            self.tableView.reloadData()
        }
    }
}

private extension ReplaceCertificateViewController
{
    @IBAction func replaceCertificate(_ sender: UIBarButtonItem)
    {
        guard let certificate = self.selectedCertificate else { return }
        
        func replace()
        {
            sender.isIndicatingActivity = true
            
            ALTAppleAPI.shared.revoke(certificate, for: self.team) { (success, error) in
                let result = Result(success, error).map { certificate }
                
                do
                {
                    let certificate = try result.get()
                    self.replacementHandler?(certificate)
                }
                catch
                {
                    DispatchQueue.main.async {
                        let toastView = RSTToastView(text: NSLocalizedString("Error Replacing Certificate", comment: ""), detailText: error.localizedDescription)
                        toastView.tintColor = .altPurple
                        toastView.show(in: self.navigationController?.view ?? self.view, duration: 2.0)
                        
                        sender.isIndicatingActivity = false
                    }
                }
            }
        }
        
        let localizedTitle = String(format: NSLocalizedString("Are you sure you want to replace %@?", comment: ""), certificate.name)
        let localizedMessage = NSLocalizedString("Any AltStore apps currently installed with this certificate will need to be refreshed.", comment: "")
        let localizedReplaceActionTitle = String(format: NSLocalizedString("Replace %@", comment: ""), certificate.name)
        
        let alertController = UIAlertController(title: localizedTitle, message: localizedMessage, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: localizedReplaceActionTitle, style: .destructive) { (action) in
            replace()
        })
        alertController.addAction(.cancel)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func cancel()
    {
        self.replacementHandler?(nil)
    }
}

extension ReplaceCertificateViewController
{
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    {
        return NSLocalizedString("You have reached the maximum number of development certificates. Please select a certificate to replace.", comment: "")
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let certificate = self.dataSource.item(at: indexPath)
        self.selectedCertificate = certificate
    }
}
