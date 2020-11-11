//
//  UIApplication+AppExtension.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/14/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import UIKit

public extension UIApplication
{
    // Cannot normally use UIApplication.shared from extensions, so we get around this by calling value(forKey:).
    class var alt_shared: UIApplication? {
        return UIApplication.value(forKey: "sharedApplication") as? UIApplication
    }
}
