//
//  AppIDComponents.swift
//  AltStore
//
//  Created by Riley Testut on 2/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class AppIDCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var bannerView: AppBannerView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.bannerView.buttonLabel.text = NSLocalizedString("Expires in", comment: "")
        self.bannerView.buttonLabel.isHidden = false
    }
}

class AppIDsCollectionReusableView: UICollectionReusableView
{
    @IBOutlet var textLabel: UILabel!
}
