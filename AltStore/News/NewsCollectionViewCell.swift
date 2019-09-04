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
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.layer.cornerRadius = 30
        self.contentView.clipsToBounds = true
        
        self.imageView.layer.cornerRadius = 30
        self.imageView.clipsToBounds = true
    }
}
