//
//  NSError+AltStore.swift
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
    
    func withLocalizedFailure(_ failure: String) -> NSError
    {
        var userInfo = self.userInfo
        userInfo[NSLocalizedFailureErrorKey] = failure
        userInfo[NSLocalizedDescriptionKey] = self.localizedDescription
        userInfo[NSLocalizedFailureReasonErrorKey] = self.localizedFailureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = self.localizedRecoverySuggestion
        
        let error = NSError(domain: self.domain, code: self.code, userInfo: userInfo)
        return error
    }
    
    func sanitizedForCoreData() -> NSError
    {
        var userInfo = self.userInfo
        userInfo[NSLocalizedFailureErrorKey] = self.localizedFailure
        userInfo[NSLocalizedDescriptionKey] = self.localizedDescription
        userInfo[NSLocalizedFailureReasonErrorKey] = self.localizedFailureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = self.localizedRecoverySuggestion
        
        // Remove non-ObjC-compliant userInfo values.
        userInfo["NSCodingPath"] = nil
        
        let error = NSError(domain: self.domain, code: self.code, userInfo: userInfo)
        return error
    }
}

protocol ALTLocalizedError: LocalizedError, CustomNSError
{
    var errorFailure: String? { get }
}

extension ALTLocalizedError
{
    var errorUserInfo: [String : Any] {
        let userInfo = [NSLocalizedDescriptionKey: self.errorDescription,
                        NSLocalizedFailureReasonErrorKey: self.failureReason,
                        NSLocalizedFailureErrorKey: self.errorFailure].compactMapValues { $0 }
        return userInfo
    }
}
