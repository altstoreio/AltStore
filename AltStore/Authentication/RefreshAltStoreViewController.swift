//
//  RefreshAltStoreViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AltSign

import Roxas

class RefreshAltStoreViewController: UIViewController
{
    var signer: ALTSigner!
    var session: ALTAppleAPISession!
    
    var completionHandler: ((Result<Void, Error>) -> Void)?
    
    @IBOutlet private var placeholderView: RSTPlaceholderView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.placeholderView.textLabel.isHidden = true
        
        self.placeholderView.detailTextLabel.textAlignment = .left
        self.placeholderView.detailTextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.placeholderView.detailTextLabel.text = NSLocalizedString("AltStore was unable to use an existing signing certificate, so it had to create a new one. This will cause any apps installed with an existing certificate to expire — including AltStore.\n\nTo prevent AltStore from expiring early, please refresh the app now. AltStore will quit once refreshing is complete.", comment: "")
    }
}

private extension RefreshAltStoreViewController
{
    @IBAction func refreshAltStore(_ sender: PillButton)
    {
        guard let altStore = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) else { return }
                
        func refresh()
        {
            sender.isIndicatingActivity = true
            
            if let progress = AppManager.shared.refreshProgress(for: altStore) ?? AppManager.shared.installationProgress(for: altStore)
            {
                // Cancel pending AltStore refresh so we can start a new one.
                progress.cancel()
            }
            
            let group = OperationGroup()
            group.signer = self.signer // Prevent us from trying to authenticate a second time.
            group.session = self.session // ^
            group.completionHandler = { (result) in
                if let error = result.error ?? result.value?.values.compactMap({ $0.error }).first
                {
                    DispatchQueue.main.async {
                        sender.progress = nil
                        sender.isIndicatingActivity = false
                        
                        let alertController = UIAlertController(title: NSLocalizedString("Failed to Refresh AltStore", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default, handler: { (action) in
                            refresh()
                        }))
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Refresh Later", comment: ""), style: .cancel, handler: { (action) in
                            self.completionHandler?(.failure(error))
                        }))
                        
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
                else
                {
                    self.completionHandler?(.success(()))
                }
            }
            
            _ = AppManager.shared.refresh([altStore], presentingViewController: self, group: group)
            sender.progress = group.progress
        }
        
        refresh()
    }
    
    @IBAction func cancel(_ sender: UIButton)
    {
        self.completionHandler?(.failure(OperationError.cancelled))
    }
}
