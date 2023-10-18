//
//  SourceHeaderView.swift
//  AltStore
//
//  Created by Riley Testut on 3/9/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

class SourceHeaderView: RSTNibView
{
    @IBOutlet private(set) var titleLabel: UILabel!
    @IBOutlet private(set) var subtitleLabel: UILabel!
    @IBOutlet private(set) var iconImageView: UIImageView!
    @IBOutlet private(set) var websiteButton: UIButton!
    
    @IBOutlet private var websiteContentView: UIView!
    @IBOutlet private var websiteButtonContainerView: UIView!
    @IBOutlet private var websiteImageView: UIImageView!
    
    @IBOutlet private var widthConstraint: NSLayoutConstraint!
    
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
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        self.iconImageView.clipsToBounds = true
        
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold)!
        let titleFont = UIFont(descriptor: fontDescriptor, size: 0.0)
        self.titleLabel.font = titleFont
        
        self.websiteButton.setTitle(nil, for: .normal)
        self.websiteButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        
        let imageConfiguration = UIImage.SymbolConfiguration(scale: .medium)
        let websiteImage = UIImage(systemName: "link", withConfiguration: imageConfiguration)
        self.websiteImageView.image = websiteImage
        
        self.websiteButtonContainerView.clipsToBounds = true
        self.websiteButtonContainerView.layer.cornerRadius = 14 // 22 - inset (8)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.iconImageView.layer.cornerRadius = self.iconImageView.bounds.midY
        
        if let titleLabel = self.websiteButton.titleLabel, self.widthConstraint.constant == 0
        {
            // Left-align website button text with subtitle by increasing width by label inset.
            let frame = self.websiteButton.convert(titleLabel.frame, from: titleLabel.superview)
            self.widthConstraint.constant = frame.minX
        }
    }
}

extension SourceHeaderView
{
    func configure(for source: Source)
    {
        self.titleLabel.text = source.name
        self.subtitleLabel.text = source.subtitle
        
        self.websiteImageView.tintColor = source.effectiveTintColor
        
        if let websiteURL = source.websiteURL
        {
            self.websiteButton.setTitle(websiteURL.absoluteString, for: .normal)
            
            self.websiteContentView.isHidden = false
            self.websiteImageView.isHidden = false
        }
        else
        {
            self.websiteButton.setTitle(nil, for: .normal)
            
            self.websiteContentView.isHidden = true
            self.websiteImageView.isHidden = true
        }
        
        Nuke.loadImage(with: source.effectiveIconURL, into: self.iconImageView)
    }
}
