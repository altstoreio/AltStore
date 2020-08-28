//
//  InstalledAppsCollectionHeaderView.swift
//  AltStore
//
//  Created by Riley Testut on 3/9/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class InstalledAppsCollectionHeaderView: UICollectionReusableView
{
    let textLabel: UILabel
    let button: UIButton
    
    override init(frame: CGRect)
    {
        self.textLabel = UILabel()
        self.textLabel.translatesAutoresizingMaskIntoConstraints = false
        self.textLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        self.textLabel.accessibilityTraits.insert(.header)
        
        self.button = UIButton(type: .system)
        self.button.translatesAutoresizingMaskIntoConstraints = false
        self.button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        
        super.init(frame: frame)
        
        self.addSubview(self.textLabel)
        self.addSubview(self.button)
        
        NSLayoutConstraint.activate([self.textLabel.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
                                     self.textLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor)])
        
        NSLayoutConstraint.activate([self.button.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
                                     self.button.firstBaselineAnchor.constraint(equalTo: self.textLabel.firstBaselineAnchor)])
        
        self.preservesSuperviewLayoutMargins = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
