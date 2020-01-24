//
//  MyAppsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 7/17/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class InstalledAppCollectionViewCell: UICollectionViewCell
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

class InstalledAppsCollectionHeaderView: UICollectionReusableView
{
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
}

class InstalledAppsCollectionFooterView: UICollectionReusableView
{
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
}

class NoUpdatesCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var blurView: UIVisualEffectView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.preservesSuperviewLayoutMargins = true
    }
}

class UpdatesCollectionHeaderView: UICollectionReusableView
{
    let button = PillButton(type: .system)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.button.translatesAutoresizingMaskIntoConstraints = false
        self.button.setTitle(">", for: .normal)
        self.addSubview(self.button)
        
        NSLayoutConstraint.activate([self.button.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20),
                                     self.button.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.button.widthAnchor.constraint(equalToConstant: 50),
                                     self.button.heightAnchor.constraint(equalToConstant: 26)])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
