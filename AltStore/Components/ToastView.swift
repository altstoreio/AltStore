//
//  ToastView.swift
//  AltStore
//
//  Created by Riley Testut on 7/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Roxas

class ToastView: RSTToastView
{
    override init(text: String, detailText detailedText: String?)
    {
        super.init(text: text, detailText: detailedText)
        
        self.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        self.layer.cornerRadius = 16
    }
}
