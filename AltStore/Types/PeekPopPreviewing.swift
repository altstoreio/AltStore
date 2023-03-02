//
//  PeekPopPreviewing.swift
//  AltStore
//
//  Created by Riley Testut on 3/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

// Conforming UIViewControllers to PeekPopPreviewing allows us to call deprecated registerForPreviewing(with:sourceView:) without warnings.
protocol PeekPopPreviewing
{
    @discardableResult
    func registerForPreviewing(with delegate: UIViewControllerPreviewingDelegate, sourceView: UIView) -> UIViewControllerPreviewing
}
