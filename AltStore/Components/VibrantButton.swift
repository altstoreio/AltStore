//
//  VibrantButton.swift
//  AltStore
//
//  Created by Riley Testut on 3/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

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
    
    private var vibrancyView: UIVisualEffectView!
    
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
        let font = UIFont.boldSystemFont(ofSize: 14)
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        
        if #available(iOS 15, *)
        {
            var backgroundConfig = UIBackgroundConfiguration.clear()
            backgroundConfig.visualEffect = blurEffect

            var config = UIButton.Configuration.plain()
            config.cornerStyle = .capsule
            config.background = backgroundConfig
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.boldSystemFont(ofSize: 14)
                return attributes
            }

            self.configuration = config
        }
        else
        {
            self.titleLabel?.font = font
            self.clipsToBounds = true
            
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.isUserInteractionEnabled = false
            self.addSubview(blurView, pinningEdgesWith: .zero)
            self.insertSubview(blurView, at: 0)
        }
        
        self.vibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: blurEffect, style: .fill)) // .fill is more vibrant than .secondaryLabel
        self.vibrancyView.isUserInteractionEnabled = false
        self.addSubview(self.vibrancyView, pinningEdgesWith: .zero)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.layer.cornerRadius = self.bounds.midY
        
        guard let vibrancyView = self.vibrancyView else { return }
        
        // Make sure content subviews are inside self.vibrancyView.contentView.
        
        if let titleLabel = self.titleLabel, titleLabel.superview != vibrancyView.contentView
        {
            vibrancyView.contentView.addSubview(titleLabel)
        }
       
        if let imageView = self.imageView, imageView.superview != vibrancyView.contentView
        {
            vibrancyView.contentView.addSubview(imageView)
        }
    }
}
