//
//  ErrorDetailsViewController.swift
//  AltServer
//
//  Created by Riley Testut on 10/4/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import AppKit

class ErrorDetailsViewController: NSViewController
{
    var error: NSError? {
        didSet {
            self.update()
        }
    }
    
    @IBOutlet private var errorCodeLabel: NSTextField!
    @IBOutlet private var detailedDescriptionLabel: NSTextField!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.detailedDescriptionLabel.preferredMaxLayoutWidth = 800
    }
}

private extension ErrorDetailsViewController
{
    func update()
    {
        if !self.isViewLoaded
        {
            self.loadView()
        }
        
        guard let error = self.error else { return }
        
        self.errorCodeLabel.stringValue = error.localizedErrorCode
        
        let font = self.detailedDescriptionLabel.font ?? NSFont.systemFont(ofSize: 12)
        let detailedDescription = error.formattedDetailedDescription(with: font)
        self.detailedDescriptionLabel.attributedStringValue = detailedDescription
    }
}

