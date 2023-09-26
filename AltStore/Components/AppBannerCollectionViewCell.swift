//
//  AppBannerCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 3/23/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class AppBannerCollectionViewCell: UICollectionViewCell
{
    let bannerView = AppBannerView(frame: .zero)
    
    private(set) var errorBadge: UIView!
    
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
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView)
        
        let errorBadge = UIView()
        errorBadge.translatesAutoresizingMaskIntoConstraints = false
        errorBadge.isHidden = true
        self.addSubview(errorBadge)
        
        // Solid background to make the X opaque white.
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .white
        errorBadge.addSubview(backgroundView)
                    
        let badgeView = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill"))
        badgeView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
        badgeView.tintColor = .systemRed
        errorBadge.addSubview(badgeView, pinningEdgesWith: .zero)
        
        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
            self.bannerView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            
            errorBadge.centerXAnchor.constraint(equalTo: self.bannerView.trailingAnchor, constant: -5),
            errorBadge.centerYAnchor.constraint(equalTo: self.bannerView.topAnchor, constant: 5),
            
            backgroundView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            backgroundView.widthAnchor.constraint(equalTo: badgeView.widthAnchor, multiplier: 0.5),
            backgroundView.heightAnchor.constraint(equalTo: badgeView.heightAnchor, multiplier: 0.5)
        ])
        
        self.errorBadge = errorBadge
    }
}
