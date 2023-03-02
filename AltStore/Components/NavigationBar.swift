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
    @IBInspectable var automaticallyAdjustsItemPositions: Bool = true
    
    private let backgroundColorView = UIView()
    
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
        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithDefaultBackground()
        standardAppearance.shadowColor = nil
        
        let edgeAppearance = UINavigationBarAppearance()
        edgeAppearance.configureWithOpaqueBackground()
        edgeAppearance.backgroundColor = self.barTintColor
        edgeAppearance.shadowColor = nil
        
        if let tintColor = self.barTintColor
        {
            let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
            
            standardAppearance.backgroundColor = tintColor
            standardAppearance.titleTextAttributes = textAttributes
            standardAppearance.largeTitleTextAttributes = textAttributes
            
            edgeAppearance.titleTextAttributes = textAttributes
            edgeAppearance.largeTitleTextAttributes = textAttributes
        }
        else
        {
            standardAppearance.backgroundColor = nil
        }
        
        self.scrollEdgeAppearance = edgeAppearance
        self.standardAppearance = standardAppearance
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        if self.backgroundColorView.superview != nil
        {
            self.insertSubview(self.backgroundColorView, at: 1)
        }
        
        if self.automaticallyAdjustsItemPositions
        {
            // We can't easily shift just the back button up, so we shift the entire content view slightly.
            for contentView in self.subviews
            {
                guard NSStringFromClass(type(of: contentView)).contains("ContentView") else { continue }
                contentView.center.y -= 2
            }
        }
    }
}
