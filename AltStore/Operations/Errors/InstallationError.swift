//
//  InstallationError.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import MarketplaceKit

struct InstallationError: CustomNSError
{
    let error: MarketplaceKitError
    
    var errorCode: Int {
        // Use same error code as MarketplaceKitError.
        return self.error._code
    }
    
    var errorUserInfo: [String : Any] {
        let failureReason = String(describing: self.error) // MarketplaceKitError conforms to CustomStringConvertible.
        
        let userInfo = [NSLocalizedFailureReasonErrorKey: failureReason]
        return userInfo
    }
}
