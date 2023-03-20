//
//  SourceAboutView.swift
//  AltStore
//
//  Created by Riley Testut on 3/9/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

class SourceAboutView: RSTNibView
{
    override var accessibilityLabel: String? {
        get { return self.accessibilityView?.accessibilityLabel }
        set { self.accessibilityView?.accessibilityLabel = newValue }
    }
    
    override open var accessibilityAttributedLabel: NSAttributedString? {
        get { return self.accessibilityView?.accessibilityAttributedLabel }
        set { self.accessibilityView?.accessibilityAttributedLabel = newValue }
    }
    
    override var accessibilityValue: String? {
        get { return self.accessibilityView?.accessibilityValue }
        set { self.accessibilityView?.accessibilityValue = newValue }
    }
    
    override open var accessibilityAttributedValue: NSAttributedString? {
        get { return self.accessibilityView?.accessibilityAttributedValue }
        set { self.accessibilityView?.accessibilityAttributedValue = newValue }
    }
    
    override open var accessibilityTraits: UIAccessibilityTraits {
        get { return self.accessibilityView?.accessibilityTraits ?? [] }
        set { self.accessibilityView?.accessibilityTraits = newValue }
    }
    
    private var originalTintColor: UIColor?
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: UIImageView!
    
    @IBOutlet var descriptionTextView: CollapsingTextView?
    @IBOutlet var websiteContentView: UIView!
    @IBOutlet var linkButton: UIButton!
    @IBOutlet var linkButtonContainerView: UIView!
    @IBOutlet var linkButtonImageView: UIImageView!
    
//    @IBOutlet var button: PillButton!
//    @IBOutlet var buttonLabel: UILabel!
//    @IBOutlet var betaBadgeView: UIView!
    
    @IBOutlet var backgroundEffectView: UIVisualEffectView!
    
    @IBOutlet private var vibrancyView: UIVisualEffectView!
    @IBOutlet private var accessibilityView: UIView!
    
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
        let boldFont = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold) ?? self.titleLabel.font.fontDescriptor
        let boldTitleFont = UIFont(descriptor: boldFont, size: 0.0)
        self.titleLabel.font = boldTitleFont
        
        
        
//        self.descriptionTextView.textContainerInset = UIEdgeInsets(top: 0, left: 14, bottom: 14, right: 12)
//        self.descriptionTextView.textContainer.lineFragmentPadding = 0
//        self.descriptionTextView.maximumNumberOfLines = 6
//        self.descriptionTextView.isScrollEnabled = false
        
//        print("[RSTLog] TextContentSize:", self.descriptionTextView.contentSize)
        
        //self.accessibilityView.accessibilityTraits.formUnion(.button)

        //self.isAccessibilityElement = false
        //self.accessibilityElements = [self.accessibilityView, self.button].compactMap { $0 }

        //self.betaBadgeView.isHidden = true
        
        let iconOutsideButton = true
        
        if #available(iOS 15, *)
        {
            self.linkButton.setTitle(nil, for: .normal)
            
            var configuration = UIButton.Configuration.tinted()
            
            if iconOutsideButton
            {
                let imageConfiguration = UIImage.SymbolConfiguration(scale: .medium)
                self.linkButtonImageView.image = UIImage(systemName: "link", withConfiguration: imageConfiguration)
                self.linkButtonImageView.isHidden = false
                
//                configuration.contentInsets.leading += 12 + 7 //12+7=19 = Centered Spacing
//                configuration.imagePadding = 33 - 7 // 33-7=26 = Centered Spacing
            }
            else
            {
                let imageConfiguration = UIImage.SymbolConfiguration(weight: .bold)
                let image = UIImage(systemName: "globe", withConfiguration: imageConfiguration)
                configuration.image = image
                
                configuration.contentInsets.leading += 12 + 7 //12+7=19 = Centered Spacing
                configuration.imagePadding = 33 - 7 // 33-7=26 = Centered Spacing
                
                self.linkButtonImageView.isHidden = true
            }
            
            

            
            
//            configuration.contentInsets.leading += 12 + 7 //12+7=19 = Centered Spacing
//            configuration.imagePadding = 33 - 7 // 33-7=26 = Centered Spacing
            configuration.baseBackgroundColor = .clear
            configuration.title = "https://altstore.io"
            configuration.titleAlignment = .leading
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return attributes
            }
            
//            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
//                var attributes = attributes
//
//                let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1).withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2)
//                attributes.font = UIFont(descriptor: fontDescriptor, size: 0.0)
//
//                return attributes
//            }
            configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return attributes
            }
            
            self.linkButton.configuration = configuration
        }
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.iconImageView.clipsToBounds = true
        self.iconImageView.layer.cornerRadius = self.iconImageView.bounds.midY
        
//        self.linkButton.clipsToBounds = true
//        self.linkButton.layer.cornerRadius = max(self.layer.cornerRadius - 14, 0) // 14 = inset from corner
        
        self.linkButtonContainerView.clipsToBounds = true
        self.linkButtonContainerView.layer.cornerRadius = 14
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
}

extension SourceAboutView
{
    func configure(for source: Source)
    {
        self.titleLabel.text = source.name
        self.subtitleLabel.text = source.caption
        
        self.linkButton.tintColor = source.effectiveTintColor
        
        if let websiteURL = source.websiteURL
        {
            self.linkButton.setTitle(websiteURL.absoluteString, for: .normal)
            
            self.websiteContentView.isHidden = false
            self.linkButtonImageView.isHidden = false
        }
        else
        {
            self.linkButton.setTitle(nil, for: .normal)
            self.websiteContentView.isHidden = true
            self.linkButtonImageView.isHidden = true
        }
        
        Nuke.loadImage(with: source.effectiveIconURL, into: self.iconImageView)
    }
}

private extension SourceAboutView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
//        self.subtitleLabel.textColor = self.originalTintColor ?? self.tintColor
    }
}
