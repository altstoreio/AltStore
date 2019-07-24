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
    
    @IBOutlet var appIconImageView: UIImageView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var updateButton: PillButton!
    @IBOutlet var versionDescriptionTitleLabel: UILabel!
    @IBOutlet var versionDescriptionTextView: CollapsingTextView!
            
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.layer.cornerRadius = 20
        self.contentView.layer.masksToBounds = true
        
        self.update()
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
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
        
        self.versionDescriptionTitleLabel.textColor = self.tintColor
        self.contentView.backgroundColor = self.tintColor.withAlphaComponent(0.1)
        
        self.updateButton.setTitleColor(self.tintColor, for: .normal)
        self.updateButton.backgroundColor = self.tintColor.withAlphaComponent(0.15)
        self.updateButton.progressTintColor = self.tintColor        
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
}
