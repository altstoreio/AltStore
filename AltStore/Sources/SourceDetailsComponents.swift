//
//  SourceDetailsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 3/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

class TextViewCollectionViewCell: UICollectionViewCell
{
    let textView = CollapsingTextView(frame: .zero)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.textView.font = UIFont.preferredFont(forTextStyle: .body)
        self.textView.isScrollEnabled = false
        self.contentView.addSubview(self.textView, pinningEdgesWith: .zero)
    }
    
    override func layoutMarginsDidChange()
    {
        super.layoutMarginsDidChange()
        
        self.textView.textContainerInset.left = self.contentView.layoutMargins.left
        self.textView.textContainerInset.right = self.contentView.layoutMargins.right
    }
    
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize
    {
        // Ensure cell is laid out so it will report correct size.
        self.layoutIfNeeded()
        
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        
        return size
    }
}
