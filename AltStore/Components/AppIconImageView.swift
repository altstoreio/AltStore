//
//  AppIconImageView.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension AppIconImageView
{
    enum Style
    {
        case icon
        case circular
    }
}

class AppIconImageView: UIImageView
{
    var style: Style = .icon {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    init(style: Style) 
    {
        self.style = style
        
        super.init(image: nil)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder) 
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
        self.backgroundColor = .white
        
        self.layer.cornerCurve = .continuous
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        switch self.style
        {
        case .icon:
            // Based off of 60pt icon having 12pt radius.
            let radius = self.bounds.height / 5
            self.layer.cornerRadius = radius
            
        case .circular:
            let radius = self.bounds.height / 2
            self.layer.cornerRadius = radius
        }
    }
}
