//
//  FeaturedComponents.swift
//  AltStore
//
//  Created by Riley Testut on 12/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

class LargeIconCollectionViewCell: UICollectionViewCell
{
    let textLabel = UILabel(frame: .zero)
    let imageView = UIImageView(frame: .zero)
    
    override init(frame: CGRect)
    {
        self.textLabel.translatesAutoresizingMaskIntoConstraints = false
        self.textLabel.textColor = .white
        self.textLabel.font = .preferredFont(forTextStyle: .headline)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.contentMode = .center
        self.imageView.tintColor = .white
        self.imageView.alpha = 0.4
        self.imageView.preferredSymbolConfiguration = .init(pointSize: 80)
        
        super.init(frame: frame)
        
        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerRadius = 16
        self.contentView.layer.cornerCurve = .continuous
        
        self.contentView.addSubview(self.textLabel)
        self.contentView.addSubview(self.imageView)
        
        NSLayoutConstraint.activate([
            self.textLabel.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
            self.textLabel.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor, constant: -4),
            
            self.imageView.centerXAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -30),
            self.imageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor, constant: 0),
            self.imageView.heightAnchor.constraint(equalTo: self.contentView.heightAnchor, constant: 0),
            self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IconButtonCollectionReusableView: UICollectionReusableView
{
    let iconButton: UIButton
    let titleButton: UIButton
    
    private let stackView: UIStackView
    
    override init(frame: CGRect)
    {
        let iconHeight = 26.0
        
        self.iconButton = UIButton(type: .custom)
        self.iconButton.translatesAutoresizingMaskIntoConstraints = false
        self.iconButton.clipsToBounds = true
        self.iconButton.layer.cornerRadius = iconHeight / 2
        
        let content = UIListContentConfiguration.plainHeader()
        self.titleButton = UIButton(type: .system)
        self.titleButton.translatesAutoresizingMaskIntoConstraints = false
        self.titleButton.titleLabel?.font = content.textProperties.font
        self.titleButton.setTitleColor(content.textProperties.color, for: .normal)
        
        self.stackView = UIStackView(arrangedSubviews: [self.iconButton, self.titleButton])
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.axis = .horizontal
        self.stackView.alignment = .center
        self.stackView.spacing = UIStackView.spacingUseSystem
        self.stackView.isLayoutMarginsRelativeArrangement = false
        
        super.init(frame: frame)
        
        self.addSubview(self.stackView)
        
        NSLayoutConstraint.activate([
            self.iconButton.heightAnchor.constraint(equalToConstant: iconHeight),
            self.iconButton.widthAnchor.constraint(equalTo: self.iconButton.heightAnchor),
            
            self.stackView.topAnchor.constraint(equalTo: self.topAnchor),
            self.stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
