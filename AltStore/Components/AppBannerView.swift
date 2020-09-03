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
    
    private var originalTintColor: UIColor?
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: AppIconImageView!
    @IBOutlet var button: PillButton!
    @IBOutlet var buttonLabel: UILabel!
    @IBOutlet var betaBadgeView: UIView!
    
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
        self.accessibilityView.accessibilityTraits.formUnion(.button)
        
        self.isAccessibilityElement = false
        self.accessibilityElements = [self.accessibilityView, self.button].compactMap { $0 }
        
        self.betaBadgeView.isHidden = true
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
}

private extension AppBannerView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        self.subtitleLabel.textColor = self.originalTintColor ?? self.tintColor        
        self.backgroundEffectView.backgroundColor = self.originalTintColor ?? self.tintColor
    }
}
