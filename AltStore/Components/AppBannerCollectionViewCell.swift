//
//  AppBannerCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 3/23/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class AppBannerCollectionViewCell: UICollectionViewListCell
{
    let bannerView = AppBannerView(frame: .zero)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        // Prevent content "squishing" when scrolling offscreen.
        self.insetsLayoutMarginsFromSafeArea = false
        self.contentView.insetsLayoutMarginsFromSafeArea = false
        self.bannerView.insetsLayoutMarginsFromSafeArea = false
        
        self.backgroundView = UIView() // Clear background
        self.selectedBackgroundView = UIView() // Disable selection highlighting.
        
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView)
        
        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
            self.bannerView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
