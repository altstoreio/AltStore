//
//  ErrorLogTableViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 9/9/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import UIKit

@objc(ErrorLogTableViewCell)
final class ErrorLogTableViewCell: UITableViewCell
{
    @IBOutlet var appIconImageView: AppIconImageView!
    
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var errorFailureLabel: UILabel!
    @IBOutlet var errorCodeLabel: UILabel!
    @IBOutlet var errorDescriptionTextView: CollapsingTextView!
    
    @IBOutlet var menuButton: UIButton!
    
    private var didLayoutSubviews = false
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        let moreButtonFrame = self.convert(self.errorDescriptionTextView.moreButton.frame, from: self.errorDescriptionTextView)
        guard moreButtonFrame.contains(point) else { return super.hitTest(point, with: event) }
        
        // Pass touches through menuButton so user can press moreButton.
        return self.errorDescriptionTextView.moreButton
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.didLayoutSubviews = true
    }
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize
    {
        if !self.didLayoutSubviews
        {
            // Ensure cell is laid out so it will report correct size.
            self.layoutIfNeeded()
        }
        
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        return size
    }
}
