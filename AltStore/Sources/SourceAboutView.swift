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
        
        //self.accessibilityView.accessibilityTraits.formUnion(.button)

        //self.isAccessibilityElement = false
        //self.accessibilityElements = [self.accessibilityView, self.button].compactMap { $0 }

        //self.betaBadgeView.isHidden = true
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.iconImageView.clipsToBounds = true
        self.iconImageView.layer.cornerRadius = self.iconImageView.bounds.midY
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
        self.subtitleLabel.text = "A home for apps that push the boundary of iOS."
        
//        let displayScale = (self.traitCollection.displayScale == 0.0) ? 1.0 : self.traitCollection.displayScale // 0.0 == "unspecified"
//        self.layer.borderWidth = 0.5
//        self.layer.borderColor = (source.tintColor ?? .altPrimary).withAlphaComponent(0.7).cgColor
        
        Nuke.loadImage(with: source.iconURL, into: self.iconImageView)
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
