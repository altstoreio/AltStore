//
//  SecureValueTransformer.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

@objc(ALTSecureValueTransformer)
public final class SecureValueTransformer: NSSecureUnarchiveFromDataTransformer
{
    public static let name = NSValueTransformerName(rawValue: "ALTSecureValueTransformer")
    
    public override static var allowedTopLevelClasses: [AnyClass] {
        let allowedClasses = super.allowedTopLevelClasses + [NSError.self]
        return allowedClasses
    }
    
    public static func register()
    {
        let transformer = SecureValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}
