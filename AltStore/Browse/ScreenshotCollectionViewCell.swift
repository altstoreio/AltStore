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
        self.imageView.layer.cornerRadius = 8
        self.imageView.layer.masksToBounds = true
        
        super.init(coder: aDecoder)
        
        self.addSubview(self.imageView, pinningEdgesWith: .zero)
    }
}
