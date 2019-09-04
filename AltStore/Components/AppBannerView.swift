//
//  AppBannerView.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas

class AppBannerView: RSTNibView
{
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: AppIconImageView!
    @IBOutlet var button: PillButton!
    @IBOutlet var betaBadgeView: UIView!
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
}

private extension AppBannerView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        self.subtitleLabel.textColor = self.tintColor
        self.button.tintColor = self.tintColor
        
        self.backgroundColor = self.tintColor.withAlphaComponent(0.1)
    }
}
