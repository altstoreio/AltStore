//
//  ScreenshotCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

@objc(ScreenshotCollectionViewCell)
class ScreenshotCollectionViewCell: UICollectionViewCell
{
    let imageView: UIImageView
    
    required init?(coder aDecoder: NSCoder)
    {
        self.imageView = UIImageView(image: nil)
        self.imageView.layer.masksToBounds = true
        
        super.init(coder: aDecoder)
        
        self.addSubview(self.imageView, pinningEdgesWith: .zero)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        if let image = self.imageView.image, (image.size.height / image.size.width) > ((16.0 / 9.0) + 0.1)
        {
            // Image aspect ratio is taller than 16:9, so assume it's an X-style screenshot and set corner radius.
            self.imageView.layer.cornerRadius = max(self.imageView.bounds.width / 9.8, 8)
        }
        else
        {
            self.imageView.layer.cornerRadius = 0
        }        
    }
}
