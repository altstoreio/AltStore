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
    let imageView = UIImageView(image: nil)
    
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
        self.imageView.layer.masksToBounds = true
        self.addSubview(self.imageView, pinningEdgesWith: .zero)
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.imageView.layer.cornerRadius = 4     
    }
}
