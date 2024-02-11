//
//  OptionalProtocol.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/11/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

// Public so we can use as generic constraint.
public protocol OptionalProtocol
{
    associatedtype Wrapped
    
    static var none: Self { get }
}

extension Optional: OptionalProtocol {}
