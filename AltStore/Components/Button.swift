//
//  Button.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class Button: UIButton
{
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 20
        return size
    }
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.setTitleColor(.white, for: .normal)
        
        self.layer.masksToBounds = true
        self.layer.cornerRadius = 8
        
        self.update()
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        self.update()
    }
    
    override var isHighlighted: Bool {
        didSet {
            self.update()
        }
    }
}

private extension Button
{
    func update()
    {
        self.backgroundColor = self.tintColor
    }
}
