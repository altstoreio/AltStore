//
//  NSError+LocalizedFailure.swift
//  AltStore
//
//  Created by Riley Testut on 3/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

extension NSError
{
    @objc(alt_localizedFailure)
    var localizedFailure: String? {
        let localizedFailure = (self.userInfo[NSLocalizedFailureErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSLocalizedFailureErrorKey) as? String)
        return localizedFailure
    }
}
