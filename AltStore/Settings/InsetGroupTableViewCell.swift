//
//  InsetGroupTableViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension InsetGroupTableViewCell
{
    @objc enum Style: Int
    {
        case single
        case top
        case middle
        case bottom
    }
}

final class InsetGroupTableViewCell: UITableViewCell
{
#if !TARGET_INTERFACE_BUILDER
    @IBInspectable var style: Style = .single {
        didSet {
            self.update()
        }
    }
#else
    @IBInspectable var style: Int = 0
#endif
    
    @IBInspectable var isSelectable: Bool = false
    
    private let separatorView = UIView()
    private let insetView = UIView()
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.selectionStyle = .none
        
        self.separatorView.translatesAutoresizingMaskIntoConstraints = false
        self.separatorView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        self.addSubview(self.separatorView)
        
        self.insetView.layer.masksToBounds = true
        self.insetView.layer.cornerRadius = 16
        
        // Get the preferred background color from Interface Builder.
        self.insetView.backgroundColor = self.backgroundColor
        self.backgroundColor = nil
        
        self.addSubview(self.insetView, pinningEdgesWith: UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15))
        self.sendSubviewToBack(self.insetView)
        
        NSLayoutConstraint.activate([self.separatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 30),
                                     self.separatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -30),
                                     self.separatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                                     self.separatorView.heightAnchor.constraint(equalToConstant: 1)])
        
        self.update()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool)
    {
        super.setSelected(selected, animated: animated)
        
        if animated
        {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        }
        else
        {
            self.update()
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool)
    {
        super.setHighlighted(highlighted, animated: animated)
        
        if animated
        {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        }
        else
        {
            self.update()
        }
    }
}

private extension InsetGroupTableViewCell
{
    func update()
    {
        switch self.style
        {
        case .single:
            self.insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            self.separatorView.isHidden = true
            
        case .top:
            self.insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            self.separatorView.isHidden = false
            
        case .middle:
            self.insetView.layer.maskedCorners = []
            self.separatorView.isHidden = false
            
        case .bottom:
            self.insetView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            self.separatorView.isHidden = true
        }
        
        if self.isSelectable && (self.isHighlighted || self.isSelected)
        {
            self.insetView.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        }
        else
        {
            self.insetView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        }
    }
}
