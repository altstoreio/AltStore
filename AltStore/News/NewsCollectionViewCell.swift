//
//  NewsCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class NewsCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var captionLabel: UILabel!
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var contentBackgroundView: UIView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.contentBackgroundView.layer.cornerRadius = 30
        self.contentBackgroundView.clipsToBounds = true
        
        self.imageView.layer.cornerRadius = 30
        self.imageView.clipsToBounds = true
    }
}
