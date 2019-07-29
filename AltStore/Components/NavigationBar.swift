//
//  NavigationBar.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class NavigationBar: UINavigationBar
{
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.barTintColor = .white
        self.shadowImage = UIImage()
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        // We can't easily shift just the back button up, so we shift the entire content view slightly.
        for contentView in self.subviews
        {
            guard NSStringFromClass(type(of: contentView)).contains("ContentView") else { continue }
            contentView.center.y -= 2
        }
    }
}
