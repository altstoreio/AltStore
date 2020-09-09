//
//  PermissionPopoverViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore

class PermissionPopoverViewController: UIViewController
{
    var permission: AppPermission!
    
    @IBOutlet private var nameLabel: UILabel!
    @IBOutlet private var descriptionLabel: UILabel!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.nameLabel.text = self.permission.type.localizedName
        self.descriptionLabel.text = self.permission.usageDescription
    }
}
