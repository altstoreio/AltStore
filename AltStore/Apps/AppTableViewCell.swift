//
//  AppTableViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

@objc class AppTableViewCell: UITableViewCell
{
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var developerLabel: UILabel!
    @IBOutlet var appIconImageView: UIImageView!
    @IBOutlet var button: UIButton!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.selectionStyle = .none
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool)
    {
        super.setHighlighted(highlighted, animated: animated)
        
        self.update()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool)
    {
        super.setSelected(selected, animated: animated)
        
        self.update()
    }
}

private extension AppTableViewCell
{
    func update()
    {
        if self.isHighlighted || self.isSelected
        {
            self.contentView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        }
        else
        {
            self.contentView.backgroundColor = .white
        }
    }
}
