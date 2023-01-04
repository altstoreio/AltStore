//
//  AppContentViewControllerCells.swift
//  AltStore
//
//  Created by Riley Testut on 7/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class PermissionCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var button: UIButton!
    @IBOutlet var textLabel: UILabel!
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.button.layer.cornerRadius = self.button.bounds.midY
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.button.backgroundColor = self.tintColor.withAlphaComponent(0.15)
        self.textLabel.textColor = self.tintColor
    }
}

final class AppContentTableViewCell: UITableViewCell
{
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize
    {
        // Ensure cell is laid out so it will report correct size.
        self.layoutIfNeeded()
        
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        
        return size
    }
}
