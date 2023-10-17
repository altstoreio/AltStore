//
//  UIFontDescriptor+Bold.swift
//  AltStore
//
//  Created by Riley Testut on 10/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

extension UIFontDescriptor
{
    func bolded() -> UIFontDescriptor
    {
        guard let descriptor = self.withSymbolicTraits(.traitBold) else { return self }
        return descriptor
    }
}
