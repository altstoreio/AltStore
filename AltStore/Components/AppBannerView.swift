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
    private var originalTintColor: UIColor?
    
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
        
        if self.tintAdjustmentMode != .dimmed
        {
            self.originalTintColor = self.tintColor
        }
        
        self.update()
    }
}

private extension AppBannerView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        self.subtitleLabel.textColor = self.originalTintColor ?? self.tintColor        
        self.backgroundEffectView.backgroundColor = self.originalTintColor ?? self.tintColor
    }
}
