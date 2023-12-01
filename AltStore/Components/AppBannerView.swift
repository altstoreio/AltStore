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
    
    enum AppAction
    {
        case install
        case open
        case update
        case custom(String)
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
        self.insetsLayoutMarginsFromSafeArea = false
        
        self.stackView.isLayoutMarginsRelativeArrangement = true
        self.stackView.preservesSuperviewLayoutMargins = true
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
    func configure(for app: AppProtocol, action: AppAction? = nil)
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
        
        if let storeApp = app.storeApp, storeApp.isPledgeRequired
        {
            // Always show button label for Patreon apps.
            self.buttonLabel.isHidden = false
            self.buttonLabel.text = storeApp.isPledged ? NSLocalizedString("Pledged", comment: "") : NSLocalizedString("Join Patreon", comment: "")
        }
        else
        {
            self.buttonLabel.isHidden = true
        }
        
        let buttonAction: AppAction
        
        if let action
        {
            buttonAction = action
        }
        else if let storeApp = app.storeApp
        {
            if let installedApp = storeApp.installedApp
            {
                // App is installed
                
                if installedApp.isUpdateAvailable
                {
                    buttonAction = .update
                }
                else
                {
                    buttonAction = .open
                }
            }
            else
            {
                // App is not installed
                buttonAction = .install
            }
        }
        else
        {
            // App is not from a source, fall back to .open
            buttonAction = .open
        }
        
        switch buttonAction
        {
        case .open:
            let buttonTitle = NSLocalizedString("Open", comment: "")
            self.button.setTitle(buttonTitle.uppercased(), for: .normal)
            self.button.accessibilityLabel = String(format: NSLocalizedString("Open %@", comment: ""), values.name)
            self.button.accessibilityValue = buttonTitle
                        
            self.button.countdownDate = nil
            
        case .update:
            let buttonTitle = NSLocalizedString("Update", comment: "")
            self.button.setTitle(buttonTitle.uppercased(), for: .normal)
            self.button.accessibilityLabel = String(format: NSLocalizedString("Update %@", comment: ""), values.name)
            self.button.accessibilityValue = buttonTitle
            
            self.button.countdownDate = nil
            
        case .custom(let buttonTitle):
            self.button.setTitle(buttonTitle, for: .normal)
            self.button.accessibilityLabel = buttonTitle
            self.button.accessibilityValue = buttonTitle
            
            self.button.countdownDate = nil
            
        case .install:
            if let storeApp = app.storeApp, storeApp.isPledgeRequired
            {
                // Pledge required
                
                if storeApp.isPledged
                {
                    let buttonTitle = NSLocalizedString("Install", comment: "")
                    self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                    self.button.accessibilityLabel = String(format: NSLocalizedString("Install %@", comment: ""), app.name)
                    self.button.accessibilityValue = buttonTitle
                }
                else if let amount = storeApp.pledgeAmount, let currencyCode = storeApp.pledgeCurrency, #available(iOS 15, *)
                {
                    let price = amount.formatted(.currency(code: currencyCode).presentation(.narrow).precision(.fractionLength(0...2)))
                    
                    let buttonTitle = String(format: NSLocalizedString("%@/mo", comment: ""), price)
                    self.button.setTitle(buttonTitle, for: .normal)
                    self.button.accessibilityLabel = String(format: NSLocalizedString("Pledge %@ a month", comment: ""), price)
                    self.button.accessibilityValue = String(format: NSLocalizedString("%@ a month", comment: ""), price)
                }
                else
                {
                    let buttonTitle = NSLocalizedString("Pledge", comment: "")
                    self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                    self.button.accessibilityLabel = buttonTitle
                    self.button.accessibilityValue = buttonTitle
                }
            }
            else
            {
                // Free app
                
                let buttonTitle = NSLocalizedString("Free", comment: "")
                self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                self.button.accessibilityLabel = String(format: NSLocalizedString("Download %@", comment: ""), app.name)
                self.button.accessibilityValue = buttonTitle
            }
            
            if let versionDate = app.storeApp?.latestSupportedVersion?.date, versionDate > Date()
            {
                self.button.countdownDate = versionDate
            }
            else
            {
                self.button.countdownDate = nil
            }
        }
        
        // Ensure PillButton is correct size before assigning progress.
        self.layoutIfNeeded()
        
        if let progress = AppManager.shared.installationProgress(for: app), progress.fractionCompleted < 1.0
        {
            self.button.progress = progress
        }
        else
        {
            self.button.progress = nil
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
