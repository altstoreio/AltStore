//
//  LicenseViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

class LicenseViewController: UIViewController
{
    var credit: CreditsViewController.Credit!
    
    private var _didAppear = false
    
    @IBOutlet private var textView: UITextView!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.title = self.credit.name
        self.textView.text = self.credit.license
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        
        // Fix incorrect initial offset on iPhone SE.
        self.textView.contentOffset.y = 0
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        _didAppear = true
    }

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        self.textView.textContainerInset.left = self.view.layoutMargins.left
        self.textView.textContainerInset.right = self.view.layoutMargins.right
        self.textView.textContainer.lineFragmentPadding = 0
        
        if !_didAppear
        {
            // Fix incorrect initial offset on iPhone SE.
            self.textView.contentOffset.y = 0
        }
    }
}
