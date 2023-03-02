//
//  DeprecatedAPIs.swift
//  AltStore
//
//  Created by Riley Testut on 3/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit

// Conform types to these protocols to call deprecated APIs without warnings.

protocol PeekPopPreviewing
{
    @discardableResult
    func registerForPreviewing(with delegate: UIViewControllerPreviewingDelegate, sourceView: UIView) -> UIViewControllerPreviewing
}

protocol LegacyBackgroundFetching
{
    func setMinimumBackgroundFetchInterval(_ minimumBackgroundFetchInterval: TimeInterval)
}
