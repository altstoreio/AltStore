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
    @IBOutlet var versionDescriptionTextView: UITextView!
    
    @IBOutlet var moreButton: UIButton!
        
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.layer.cornerRadius = 20
        self.contentView.layer.masksToBounds = true
        
        self.versionDescriptionTextView.textContainerInset = .zero
        self.versionDescriptionTextView.textContainer.lineFragmentPadding = 0
        self.versionDescriptionTextView.textContainer.lineBreakMode = .byTruncatingTail
        self.versionDescriptionTextView.textContainer.heightTracksTextView = true
        
        self.update()
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        let textContainer = self.versionDescriptionTextView.textContainer
        
        switch self.mode
        {
        case .collapsed:
            // Extra wide to make sure it wraps to next line.
            let frame = CGRect(x: textContainer.size.width - self.moreButton.bounds.width - 8,
                               y: textContainer.size.height - 4,
                               width: textContainer.size.width,
                               height: textContainer.size.height)
            
            textContainer.maximumNumberOfLines = 2
            textContainer.exclusionPaths = [UIBezierPath(rect: frame)]
            
            if let font = self.versionDescriptionTextView.font, self.versionDescriptionTextView.bounds.height > font.lineHeight * 1.5
            {
                self.moreButton.isHidden = false
            }
            else
            {
                // One (or less) lines, so hide more button.
                self.moreButton.isHidden = true
            }
            
        case .expanded:
            textContainer.maximumNumberOfLines = 10
            textContainer.exclusionPaths = []
            
            self.moreButton.isHidden = true
        }
        
        self.versionDescriptionTextView.invalidateIntrinsicContentSize()
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
        self.versionDescriptionTitleLabel.textColor = self.tintColor
        self.contentView.backgroundColor = self.tintColor.withAlphaComponent(0.1)
        
        self.updateButton.setTitleColor(self.tintColor, for: .normal)
        self.updateButton.backgroundColor = self.tintColor.withAlphaComponent(0.15)
        self.updateButton.progressTintColor = self.tintColor        
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
}
