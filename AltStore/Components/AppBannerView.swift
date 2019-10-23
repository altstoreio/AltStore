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
    @IBOutlet var buttonLabel: UILabel!
    @IBOutlet var betaBadgeView: UIView!
    
    @IBOutlet var backgroundEffectView: UIVisualEffectView!
    @IBOutlet private var vibrancyView: UIVisualEffectView!
    
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
        
        self.backgroundEffectView.backgroundColor = self.tintColor
    }
}
