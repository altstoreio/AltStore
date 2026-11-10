//
//  UIView+CompactHeight.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension UIView
{
    var isExtraCompactHeight: Bool {
        // Use the current view size so folding, rotation, and window resizing are reflected.
        return self.bounds.height < 600
    }
}
