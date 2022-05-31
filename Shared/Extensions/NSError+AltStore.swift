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
    
    @objc(alt_localizedDebugDescription)
    var localizedDebugDescription: String? {
        let debugDescription = (self.userInfo[NSDebugDescriptionErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSDebugDescriptionErrorKey) as? String)
        return debugDescription
    }
    
    @objc(alt_errorWithLocalizedFailure:)
    func withLocalizedFailure(_ failure: String) -> NSError
    {
        var userInfo = self.userInfo
        userInfo[NSLocalizedFailureErrorKey] = failure
        
        if let failureReason = self.localizedFailureReason
        {
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        }
        else if self.localizedFailure == nil && self.localizedFailureReason == nil && self.localizedDescription.contains(self.localizedErrorCode)
        {
            // Default localizedDescription, so replace with just the localized error code portion.
            userInfo[NSLocalizedFailureReasonErrorKey] = "(\(self.localizedErrorCode).)"
        }
        else
        {
            userInfo[NSLocalizedFailureReasonErrorKey] = self.localizedDescription
        }
        
        if let localizedDescription = NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSLocalizedDescriptionKey) as? String
        {
            userInfo[NSLocalizedDescriptionKey] = localizedDescription
        }
        
        // Don't accidentally remove localizedDescription from dictionary
        // userInfo[NSLocalizedDescriptionKey] = NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSLocalizedDescriptionKey) as? String
        
        if let recoverySuggestion = self.localizedRecoverySuggestion
        {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        }
        
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
        
        // Remove userInfo values that don't conform to NSSecureEncoding.
        userInfo = userInfo.filter { (key, value) in
            return (value as AnyObject) is NSSecureCoding
        }
        
        // Sanitize underlying errors.
        if let underlyingError = userInfo[NSUnderlyingErrorKey] as? Error
        {
            let sanitizedError = (underlyingError as NSError).sanitizedForCoreData()
            userInfo[NSUnderlyingErrorKey] = sanitizedError
        }
        
        if #available(iOS 14.5, macOS 11.3, *), let underlyingErrors = userInfo[NSMultipleUnderlyingErrorsKey] as? [Error]
        {
            let sanitizedErrors = underlyingErrors.map { ($0 as NSError).sanitizedForCoreData() }
            userInfo[NSMultipleUnderlyingErrorsKey] = sanitizedErrors
        }
        
        let error = NSError(domain: self.domain, code: self.code, userInfo: userInfo)
        return error
    }
}

extension Error
{
    var underlyingError: Error? {
        let underlyingError = (self as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        return underlyingError
    }
    
    var localizedErrorCode: String {
        let localizedErrorCode = String(format: NSLocalizedString("%@ error %@", comment: ""), (self as NSError).domain, (self as NSError).code as NSNumber)
        return localizedErrorCode
    }
}

protocol ALTLocalizedError: LocalizedError, CustomNSError
{
    var failure: String? { get }
    
    var underlyingError: Error? { get }
}

extension ALTLocalizedError
{
    var errorUserInfo: [String : Any] {
        let userInfo = ([
            NSLocalizedDescriptionKey: self.errorDescription,
            NSLocalizedFailureReasonErrorKey: self.failureReason,
            NSLocalizedFailureErrorKey: self.failure,
            NSUnderlyingErrorKey: self.underlyingError
        ] as [String: Any?]).compactMapValues { $0 }
        return userInfo
    }
    
    var underlyingError: Error? {
        // Error's default implementation calls errorUserInfo,
        // but ALTLocalizedError.errorUserInfo calls underlyingError.
        // Return nil to prevent infinite recursion.
        return nil
    }
    
    var errorDescription: String? {
        guard let errorFailure = self.failure else { return (self.underlyingError as NSError?)?.localizedDescription }
        guard let failureReason = self.failureReason else { return errorFailure }
        
        let errorDescription = errorFailure + " " + failureReason
        return errorDescription
    }
    
    var failureReason: String? { (self.underlyingError as NSError?)?.localizedDescription }
    var recoverySuggestion: String? { (self.underlyingError as NSError?)?.localizedRecoverySuggestion }
    var helpAnchor: String? { (self.underlyingError as NSError?)?.helpAnchor }
}
