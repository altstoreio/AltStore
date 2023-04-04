//
//  VibrantButton.swift
//  AltStore
//
//  Created by Riley Testut on 3/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

private let preferredFont = UIFont.boldSystemFont(ofSize: 14)

class VibrantButton: UIButton
{
    var title: String? {
        didSet {
            if #available(iOS 15, *)
            {
                self.configuration?.title = self.title
            }
            else
            {
                self.setTitle(self.title, for: .normal)
            }
        }
    }
    
    var image: UIImage? {
        didSet {
            if #available(iOS 15, *)
            {
                self.configuration?.image = self.image
            }
            else
            {
                self.setImage(self.image, for: .normal)
            }
        }
    }
    
    var contentInsets: NSDirectionalEdgeInsets = .zero {
        didSet {
            if #available(iOS 15, *)
            {
                self.configuration?.contentInsets = self.contentInsets
            }
            else
            {
                self.contentEdgeInsets = UIEdgeInsets(top: self.contentInsets.top, left: self.contentInsets.leading, bottom: self.contentInsets.bottom, right: self.contentInsets.trailing)
            }
        }
    }
    
    override var isIndicatingActivity: Bool {
        didSet {
            guard #available(iOS 15, *) else { return }
            self.updateConfiguration()
        }
    }
    
    private let vibrancyView = UIVisualEffectView(effect: nil)
    
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
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .fill) // .fill is more vibrant than .secondaryLabel
        
        if #available(iOS 15, *)
        {
            var backgroundConfig = UIBackgroundConfiguration.clear()
            backgroundConfig.visualEffect = blurEffect

            var config = UIButton.Configuration.plain()
            config.cornerStyle = .capsule
            config.background = backgroundConfig
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] (attributes) in
                var attributes = attributes
                attributes.font = preferredFont
                
                if let self, self.isIndicatingActivity
                {
                    // Hide title when indicating activity, but without changing intrinsicContentSize.
                    attributes.foregroundColor = UIColor.clear
                }
                
                return attributes
            }
            
            self.configuration = config
        }
        else
        {
            self.clipsToBounds = true
            self.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8) // Add padding.
            
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.isUserInteractionEnabled = false
            self.addSubview(blurView, pinningEdgesWith: .zero)
            self.insertSubview(blurView, at: 0)
        }
        
        self.vibrancyView.effect = vibrancyEffect
        self.vibrancyView.isUserInteractionEnabled = false
        self.addSubview(self.vibrancyView, pinningEdgesWith: .zero)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.layer.cornerRadius = self.bounds.midY
                
        // Make sure content subviews are inside self.vibrancyView.contentView.
        
        if let titleLabel = self.titleLabel, titleLabel.superview != self.vibrancyView.contentView
        {
            self.vibrancyView.contentView.addSubview(titleLabel)
        }
       
        if let imageView = self.imageView, imageView.superview != self.vibrancyView.contentView
        {
            self.vibrancyView.contentView.addSubview(imageView)
        }
        
        if self.activityIndicatorView.superview != self.vibrancyView.contentView
        {
            self.vibrancyView.contentView.addSubview(self.activityIndicatorView)
        }
        
        if #unavailable(iOS 15)
        {
            // Update font after init because the original titleLabel is replaced.
            self.titleLabel?.font = preferredFont
        }
    }
}
