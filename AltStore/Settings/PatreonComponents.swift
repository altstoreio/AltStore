//
//  PatreonComponents.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class PatronCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var textLabel: UILabel!
}

class PatronsHeaderView: UICollectionReusableView
{
    let textLabel = UILabel()
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.textLabel.font = UIFont.boldSystemFont(ofSize: 17)
        self.textLabel.textColor = .white
        self.addSubview(self.textLabel, pinningEdgesWith: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PatronsFooterView: UICollectionReusableView
{
    let button = UIButton(type: .system)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.button.translatesAutoresizingMaskIntoConstraints = false
        self.button.activityIndicatorView.style = .white
        self.button.titleLabel?.textColor = .white
        self.addSubview(self.button)
        
        NSLayoutConstraint.activate([self.button.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                                     self.button.centerYAnchor.constraint(equalTo: self.centerYAnchor)])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class AboutPatreonHeaderView: UICollectionReusableView
{
    @IBOutlet var supportButton: UIButton!
    @IBOutlet var accountButton: UIButton!
    @IBOutlet var textView: UITextView!
    
    @IBOutlet private var imageView: UIImageView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.imageView.clipsToBounds = true
        self.imageView.layer.cornerRadius = self.imageView.bounds.midY
        
        self.textView.clipsToBounds = true
        self.textView.layer.cornerRadius = 20
        self.textView.textContainer.lineFragmentPadding = 0
        
        for button in [self.supportButton!, self.accountButton!]
        {
            button.clipsToBounds = true
            button.layer.cornerRadius = 16
        }
    }
    
    override func layoutMarginsDidChange()
    {
        super.layoutMarginsDidChange()
        
        self.textView.textContainerInset = UIEdgeInsets(top: self.layoutMargins.left, left: self.layoutMargins.left, bottom: self.layoutMargins.right, right: self.layoutMargins.right)
    }
}

