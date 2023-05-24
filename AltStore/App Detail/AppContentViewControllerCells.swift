//
//  AppContentViewControllerCells.swift
//  AltStore
//
//  Created by Riley Testut on 7/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class AppContentTableViewCell: UITableViewCell
{
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize
    {
        // Ensure cell is laid out so it will report correct size.
        self.layoutIfNeeded()
        
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        
        return size
    }
}
