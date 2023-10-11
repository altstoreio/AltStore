//
//  AppScreenshotCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 10/11/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore

class AppScreenshotCollectionViewCell: UICollectionViewCell
{
    let imageView: UIImageView
    
    var aspectRatio: CGSize = AppScreenshot.defaultAspectRatio {
        didSet {
            self.updateAspectRatio()
        }
    }
    
    private var isRounded: Bool = false {
        didSet {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    private var aspectRatioConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect)
    {
        self.imageView = UIImageView(frame: .zero)
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerCurve = .continuous
        self.imageView.layer.borderColor = UIColor.tertiaryLabel.cgColor
                
        super.init(frame: frame)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.imageView)
        
        let widthConstraint = self.imageView.widthAnchor.constraint(equalTo: self.contentView.widthAnchor)
        widthConstraint.priority = UILayoutPriority(999)
        
        let heightConstraint = self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor)
        heightConstraint.priority = UILayoutPriority(999)
        
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            self.imageView.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor),
            self.imageView.heightAnchor.constraint(lessThanOrEqualTo: self.contentView.heightAnchor),
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor)
        ])
        
        self.updateAspectRatio()
        self.updateTraits()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) 
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        self.updateTraits()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        guard self.imageView.bounds.width != 0 else {
            self.setNeedsLayout()
            return
        }
        
        if self.isRounded
        {
            let cornerRadius = self.imageView.bounds.width / 9.0 // Based on iPhone 15
            self.imageView.layer.cornerRadius = cornerRadius
        }
        else
        {
            let cornerRadius = self.imageView.bounds.width / 25.0 // Based on iPhone 8
            self.imageView.layer.cornerRadius = cornerRadius
        }
    }
}

private extension AppScreenshotCollectionViewCell
{
    func updateAspectRatio()
    {
        self.aspectRatioConstraint?.isActive = false
        
        self.aspectRatioConstraint = self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor, multiplier: self.aspectRatio.width / self.aspectRatio.height)
        self.aspectRatioConstraint?.isActive = true
        
        let aspectRatio: Double
        if self.aspectRatio.width > self.aspectRatio.height
        {
            aspectRatio = self.aspectRatio.height / self.aspectRatio.width
        }
        else
        {
            aspectRatio = self.aspectRatio.width / self.aspectRatio.height
        }
        
        let tolerance = 0.001 as Double
        let modernAspectRatio = AppScreenshot.defaultAspectRatio.width / AppScreenshot.defaultAspectRatio.height
        
        let isRounded = (aspectRatio >= modernAspectRatio - tolerance) && (aspectRatio <= modernAspectRatio + tolerance)
        self.isRounded = isRounded
    }
    
    func updateTraits()
    {
        let displayScale = (self.traitCollection.displayScale == 0.0) ? 1.0 : self.traitCollection.displayScale
        self.imageView.layer.borderWidth = 1.0 / displayScale
    }
}
