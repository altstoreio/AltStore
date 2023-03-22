//
//  SourceDetailsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 3/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

import Roxas

@objc(AppBannerViewCell)
class AppBannerViewCell: UICollectionViewCell
{
    let bannerView: AppBannerView
    
    override init(frame: CGRect)
    {
        self.bannerView = AppBannerView(frame: .zero)
        
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        self.bannerView = AppBannerView(frame: .zero)
        
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView, pinningEdgesWith: .zero)
    }
}

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

class ButtonView: UICollectionReusableView
{
    let button: UIButton
    
//    var bottomSpacing: Double {
//        get { self.bottomConstraint.constant }
//        set { self.bottomConstraint.constant = newValue }
//    }
//    private var bottomConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect)
    {
        self.button = UIButton(type: .system)
        self.button.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: frame)
        
        self.addSubview(self.button)
        
//        self.bottomConstraint = self.bottomAnchor.constraint(equalTo: self.button.bottomAnchor)
        
        // Constrain to top, leading, trailing, but allow arbitrary bottom spacing.
        NSLayoutConstraint.activate([
//            self.bottomConstraint,
            self.button.topAnchor.constraint(equalTo: self.topAnchor),
            self.button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TitleView: UICollectionReusableView
{
    let label: UILabel
    
    override init(frame: CGRect)
    {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withSymbolicTraits(.traitBold)!
        let font = UIFont(descriptor: fontDescriptor, size: 0.0)
        
        self.label = UILabel(frame: .zero)
        
        super.init(frame: frame)
        
        self.label.font = font
        self.addSubview(self.label, pinningEdgesWith: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
