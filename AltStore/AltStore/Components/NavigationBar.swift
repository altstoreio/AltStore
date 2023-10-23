//
//  NavigationBar.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class NavigationBarAppearance: UINavigationBarAppearance
{
    // We sometimes need to ignore user interaction so
    // we can tap items underneath the navigation bar.
    var ignoresUserInteraction: Bool = false
    
    override func copy(with zone: NSZone? = nil) -> Any
    {
        let copy = super.copy(with: zone) as! NavigationBarAppearance
        copy.ignoresUserInteraction = self.ignoresUserInteraction
        return copy
    }
}

class NavigationBar: UINavigationBar
{    
    @IBInspectable var automaticallyAdjustsItemPositions: Bool = true
    
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
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        if let appearance = self.topItem?.standardAppearance as? NavigationBarAppearance, appearance.ignoresUserInteraction
        {
            // Ignore touches.
            return nil
        }
        
        return super.hitTest(point, with: event)
    }
}
