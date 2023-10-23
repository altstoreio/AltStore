//
//  ErrorDetailsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/5/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore

class ErrorDetailsViewController: UIViewController
{
    var loggedError: LoggedError?
    
    @IBOutlet private var textView: UITextView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        if let error = self.loggedError?.error
        {
            self.title = error.localizedErrorCode
            
            let font = self.textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            let detailedDescription = error.formattedDetailedDescription(with: font)
            self.textView.attributedText = detailedDescription
        }
        else
        {
            self.title = NSLocalizedString("Error Details", comment: "")
        }
        
        self.navigationController?.navigationBar.tintColor = .altPrimary
        
        if #available(iOS 15, *), let sheetController = self.navigationController?.sheetPresentationController
        {
            sheetController.detents = [.medium(), .large()]
            sheetController.selectedDetentIdentifier = .medium
            sheetController.prefersGrabberVisible = true
        }
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.textView.textContainerInset.left = self.view.layoutMargins.left
        self.textView.textContainerInset.right = self.view.layoutMargins.right
    }
}
