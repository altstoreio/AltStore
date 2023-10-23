//
//  UpdateCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension UpdateCollectionViewCell
{
    enum Mode
    {
        case collapsed
        case expanded
    }
}

@objc class UpdateCollectionViewCell: UICollectionViewCell
{
    var mode: Mode = .expanded {
        didSet {
            self.update()
        }
    }
    
    @IBOutlet var bannerView: AppBannerView!
    @IBOutlet var versionDescriptionTitleLabel: UILabel!
    @IBOutlet var versionDescriptionTextView: CollapsingTextView!
    
    @IBOutlet private var blurView: UIVisualEffectView!
    
    private var originalTintColor: UIColor?
            
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        // Prevent temporary unsatisfiable constraint errors due to UIView-Encapsulated-Layout constraints.
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.bannerView.backgroundEffectView.isHidden = true
        self.bannerView.button.setTitle(NSLocalizedString("UPDATE", comment: ""), for: .normal)
                
        self.blurView.layer.cornerRadius = 20
        self.blurView.layer.masksToBounds = true
        
        self.update()
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        if self.tintAdjustmentMode != .dimmed
        {
            self.originalTintColor = self.tintColor
        }
        
        self.update()
    }
    
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes)
    {
        // Animates transition to new attributes.
        let animator = UIViewPropertyAnimator(springTimingParameters: UISpringTimingParameters()) {
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        let view = super.hitTest(point, with: event)
        
        if view == self.versionDescriptionTextView
        {
            // Forward touches on the text view (but not on the nested "more" button)
            // so cell selection works as expected.
            return self
        }
        else
        {
            return view
        }
    }
}

private extension UpdateCollectionViewCell
{
    func update()
    {
        switch self.mode
        {
        case .collapsed: self.versionDescriptionTextView.isCollapsed = true
        case .expanded: self.versionDescriptionTextView.isCollapsed = false
        }
        
        self.versionDescriptionTitleLabel.textColor = self.originalTintColor ?? self.tintColor
        self.blurView.backgroundColor = self.originalTintColor ?? self.tintColor
        self.bannerView.button.progressTintColor = self.originalTintColor ?? self.tintColor
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
}
