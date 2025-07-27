//
//  AddSourceTextFieldCell.swift
//  AltStore
//
//  Created by Riley Testut on 10/17/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

class AddSourceTextFieldCell: UICollectionViewCell
{
    let textField: UITextField
    
    private let backgroundEffectView: UIVisualEffectView
    private let imageView: UIImageView
    
    override init(frame: CGRect)
    {
        #if MARKETPLACE
        let placeholder = "marketplace.altstore.io"
        #else
        let placeholder = "apps.altstore.io"
        #endif
        
        self.textField = UITextField(frame: frame)
        self.textField.translatesAutoresizingMaskIntoConstraints = false
        self.textField.placeholder = placeholder
        self.textField.textContentType = .URL
        self.textField.keyboardType = .URL
        self.textField.returnKeyType = .done
        self.textField.autocapitalizationType = .none
        self.textField.autocorrectionType = .no
        self.textField.spellCheckingType = .no
        self.textField.enablesReturnKeyAutomatically = true
        self.textField.tintColor = .altPrimary
        self.textField.textColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark
            {
                //TODO: Change once we update UIColor.altPrimary to match 2.0 icon.
                return UIColor(resource: .gradientTop)
            }
            else
            {
                return UIColor.altPrimary
            }
        }
        
        let blurEffect = UIBlurEffect(style: .systemChromeMaterial)
        self.backgroundEffectView = UIVisualEffectView(effect: blurEffect)
        self.backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundEffectView.clipsToBounds = true
        self.backgroundEffectView.backgroundColor = .altPrimary
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let image = UIImage(systemName: "link", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        self.imageView = UIImageView(image: image)
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.contentMode = .center
        self.imageView.tintColor = .altPrimary
        
        super.init(frame: frame)
        
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.backgroundEffectView.contentView.addSubview(self.imageView)
        self.backgroundEffectView.contentView.addSubview(self.textField)
        self.contentView.addSubview(self.backgroundEffectView)
        
        NSLayoutConstraint.activate([
            self.backgroundEffectView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.backgroundEffectView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            self.backgroundEffectView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.backgroundEffectView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            
            self.imageView.widthAnchor.constraint(equalToConstant: 44),
            self.imageView.heightAnchor.constraint(equalToConstant: 44),
            self.imageView.centerYAnchor.constraint(equalTo: self.backgroundEffectView.centerYAnchor),
            
            self.textField.topAnchor.constraint(equalTo: self.backgroundEffectView.topAnchor, constant: 15),
            self.textField.bottomAnchor.constraint(equalTo: self.backgroundEffectView.bottomAnchor, constant: -15),
            self.textField.trailingAnchor.constraint(equalTo: self.backgroundEffectView.trailingAnchor, constant: -15),
            
            self.imageView.leadingAnchor.constraint(equalTo: self.backgroundEffectView.leadingAnchor, constant: 15),
            self.textField.leadingAnchor.constraint(equalToSystemSpacingAfter: self.imageView.trailingAnchor, multiplier: 1.0),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.backgroundEffectView.layer.cornerRadius = self.backgroundEffectView.bounds.midY
    }
}
