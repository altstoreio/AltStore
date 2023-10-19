//
//  UINavigationBarAppearance+TintColor.swift
//  AltStore
//
//  Created by Riley Testut on 4/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

extension UINavigationBarAppearance
{
    func configureWithTintColor(_ tintColor: UIColor)
    {
        let buttonAppearance = UIBarButtonItemAppearance(style: .plain)
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: tintColor]
        self.buttonAppearance = buttonAppearance
        
        let backButtonImage = UIImage(systemName: "chevron.backward")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        self.setBackIndicatorImage(backButtonImage, transitionMaskImage: backButtonImage)
    }
}
