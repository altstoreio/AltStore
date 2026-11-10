//
//  InstructionsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class InstructionsViewController: UIViewController
{
    var completionHandler: (() -> Void)?
    
    var showsBottomButton: Bool = false
    
    private var defaultContentMargins: UIEdgeInsets = .zero

    @IBOutlet private var contentStackView: UIStackView!
    @IBOutlet private var dismissButton: UIButton!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.defaultContentMargins = self.contentStackView.layoutMargins
        
        self.dismissButton.clipsToBounds = true
        self.dismissButton.layer.cornerRadius = 16
        
        if self.showsBottomButton
        {
            self.navigationItem.hidesBackButton = true
        }
        else
        {
            self.dismissButton.isHidden = true
        }
    }

    override func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()

        var margins = self.defaultContentMargins
        if self.view.isExtraCompactHeight
        {
            margins.top = 0
            margins.bottom = margins.left
        }

        if self.contentStackView.layoutMargins != margins
        {
            self.contentStackView.layoutMargins = margins
        }
    }
}

private extension InstructionsViewController
{
    @IBAction func dismiss()
    {
        self.completionHandler?()
    }
}
