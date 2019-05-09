//
//  AppIconImageView.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class AppIconImageView: UIImageView
{
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
        
        self.layer.borderWidth = 0.5
        self.layer.borderColor = UIColor.lightGray.cgColor
        
        // Allows us to match system look for app icons.
        if self.layer.responds(to: Selector(("continuousCorners")))
        {
            self.layer.setValue(true, forKey: "continuousCorners")
        }
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        // Based off of 60pt icon having 12pt radius.
        let radius = self.bounds.height / 5
        self.layer.cornerRadius = radius
    }
}
