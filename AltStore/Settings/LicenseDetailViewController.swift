//
//  LicenseDetailViewController.swift
//  AltStore
//
//  Created by Kevin Romero Peces-Barba on 07/10/2019.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class LicenseDetailViewController: UITableViewController
{
    @IBOutlet weak var copyrightLabel: UILabel!
    @IBOutlet weak var licenseTextView: UITextView!
    
    var license: LicenseItem?

    override func viewDidLoad()
    {
        super.viewDidLoad()

        guard let product = license?.product,
            let copyright = license?.copyright,
            let license = license?.license else
        {
            dismiss(animated: true)
            return
        }

        navigationItem.title = product
        copyrightLabel.text = copyright.isEmpty ?  "(no copyright line)" : copyright
        licenseTextView.text = license.isEmpty ? "(no license text)" : license
    }
}
