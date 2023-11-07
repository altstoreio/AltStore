//
//  VibrantBackgroundView.swift
//  AltStore
//
//  Created by Riley Testut on 11/7/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

class VibrantBackgroundView: UICollectionReusableView
{
    private let visualEffectView: UIVisualEffectView
    
    override init(frame: CGRect)
    {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .fill)
        
        let vibrancyEffectView = UIVisualEffectView(effect: vibrancyEffect)
        
        self.visualEffectView = UIVisualEffectView(effect:blurEffect)
        
        
        super.init(frame: frame)
        
        self.visualEffectView.contentView.addSubview(vibrancyEffectView, pinningEdgesWith: .zero)
//        vibrancyEffectView.contentView.backgroundColor = .white.withAlphaComponent(0.2)
        
        self.addSubview(self.visualEffectView, pinningEdgesWith: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
