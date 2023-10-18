//
//  AppBannerView.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

extension AppBannerView
{
    enum Style
    {
        case app
        case source
    }
}

class AppBannerView: RSTNibView
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
    
    var style: Style = .app
    
    private var originalTintColor: UIColor?
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: AppIconImageView!
    @IBOutlet var button: PillButton!
    @IBOutlet var buttonLabel: UILabel!
    @IBOutlet var betaBadgeView: UIView!
    
    @IBOutlet var backgroundEffectView: UIVisualEffectView!
    
    @IBOutlet private var vibrancyView: UIVisualEffectView!
    @IBOutlet private var stackView: UIStackView!
    @IBOutlet private var accessibilityView: UIView!
    
    @IBOutlet private var iconImageViewHeightConstraint: NSLayoutConstraint!
    
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
        self.accessibilityView.accessibilityTraits.formUnion(.button)
        
        self.isAccessibilityElement = false
        self.accessibilityElements = [self.accessibilityView, self.button].compactMap { $0 }
        
        self.betaBadgeView.isHidden = true
        
        self.layoutMargins = self.stackView.layoutMargins
        self.stackView.preservesSuperviewLayoutMargins = true
        self.stackView.isLayoutMarginsRelativeArrangement = true
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

extension AppBannerView
{
    func configure(for app: AppProtocol)
    {
        struct AppValues
        {
            var name: String
            var developerName: String? = nil
            var isBeta: Bool = false
            
            init(app: AppProtocol)
            {
                self.name = app.name
                
                guard let storeApp = (app as? StoreApp) ?? (app as? InstalledApp)?.storeApp else { return }
                self.developerName = storeApp.developerName
                
                if storeApp.isBeta
                {
                    self.name = String(format: NSLocalizedString("%@ beta", comment: ""), app.name)
                    self.isBeta = true
                }
            }
        }
        
        self.style = .app

        let values = AppValues(app: app)
        self.titleLabel.text = app.name // Don't use values.name since that already includes "beta".
        self.betaBadgeView.isHidden = !values.isBeta

        if let developerName = values.developerName
        {
            self.subtitleLabel.text = developerName
            self.accessibilityLabel = String(format: NSLocalizedString("%@ by %@", comment: ""), values.name, developerName)
        }
        else
        {
            self.subtitleLabel.text = NSLocalizedString("Sideloaded", comment: "")
            self.accessibilityLabel = values.name
        }
    }
    
    func configure(for source: Source)
    {
        self.style = .source
        
        let subtitle: String
        if let text = source.subtitle
        {
            subtitle = text
        }
        else if let scheme = source.sourceURL.scheme
        {
            subtitle = source.sourceURL.absoluteString.replacingOccurrences(of: scheme + "://", with: "")
        }
        else
        {
            subtitle = source.sourceURL.absoluteString
        }
        
        self.titleLabel.text = source.name
        self.subtitleLabel.text = subtitle
        
        let tintColor = source.effectiveTintColor ?? .altPrimary
        self.tintColor = tintColor
        
        let accessibilityLabel = source.name + "\n" + subtitle
        self.accessibilityLabel = accessibilityLabel
    }
}

private extension AppBannerView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        let tintColor = self.originalTintColor ?? self.tintColor
        self.subtitleLabel.textColor = tintColor
        
        switch self.style
        {
        case .app:
            self.directionalLayoutMargins.trailing = self.stackView.directionalLayoutMargins.trailing
            
            self.iconImageViewHeightConstraint.constant = 60
            self.iconImageView.style = .icon
            
            self.titleLabel.textColor = .label
            
            self.button.style = .pill
            
            self.backgroundEffectView.contentView.backgroundColor = UIColor(resource: .blurTint)
            self.backgroundEffectView.backgroundColor = tintColor
            
        case .source:
            self.directionalLayoutMargins.trailing = 20
            
            self.iconImageViewHeightConstraint.constant = 44
            self.iconImageView.style = .circular
            
            self.titleLabel.textColor = .white
            
            self.button.style = .custom
            
            self.backgroundEffectView.contentView.backgroundColor = tintColor?.adjustedForDisplay
            self.backgroundEffectView.backgroundColor = nil
            
            if let tintColor, tintColor.isTooBright
            {
                let textVibrancyEffect = UIVibrancyEffect(blurEffect: .init(style: .systemChromeMaterialLight), style: .fill)
                self.vibrancyView.effect = textVibrancyEffect
            }
            else
            {
                // Thinner == more dull
                let textVibrancyEffect = UIVibrancyEffect(blurEffect: .init(style: .systemThinMaterialDark), style: .secondaryLabel)
                self.vibrancyView.effect = textVibrancyEffect
            }
        }
    }
}
