//
//  CodableError.swift
//  AltKit
//
//  Created by Riley Testut on 3/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

// Can only automatically conform ALTServerError.Code to Codable, not ALTServerError itself
extension ALTServerError.Code: Codable {}

private extension ErrorUserInfoKey
{
    static let altLocalizedDescription: String = "ALTLocalizedDescription"
    static let altLocalizedFailureReason: String = "ALTLocalizedFailureReason"
    static let altLocalizedRecoverySuggestion: String = "ALTLocalizedRecoverySuggestion"
    static let altDebugDescription: String = "ALTDebugDescription"
}

extension CodableError
{
    enum UserInfoValue: Codable
    {
        case unknown(Any?)
        case string(String)
        case number(Int)
        case error(NSError)
        case codableError(CodableError)
        indirect case array([UserInfoValue])
        indirect case dictionary([String: UserInfoValue])
        
        var value: Any? {
            switch self
            {
            case .unknown(let value): return value
            case .string(let string): return string
            case .number(let number): return number
            case .error(let error): return error
            case .codableError(let error): return error.error
            case .array(let array): return array.compactMap { $0.value } // .compactMap instead of .map to ensure nil values are removed.
            case .dictionary(let dictionary): return dictionary.compactMapValues { $0.value } // .compactMapValues instead of .mapValues to ensure nil values are removed.
            }
        }
        
        var codableValue: Codable? {
            switch self
            {
            case .unknown, .string, .number: return self.value as? Codable
            case .codableError(let error): return error
            case .error(let nsError):
                // Ignore error because we don't want to fail completely if error contains invalid user info value.
                let sanitizedError = nsError.sanitizedForSerialization()
                let data = try? NSKeyedArchiver.archivedData(withRootObject: sanitizedError, requiringSecureCoding: true)
                return data
                
            case .array(let array): return array
            case .dictionary(let dictionary): return dictionary
            }
        }
        
        init(_ rawValue: Any?)
        {
            switch rawValue
            {
            case let string as String: self = .string(string)
            case let number as Int: self = .number(number)
            case let number as UInt: self = .number(Int(number)) // No idea why this is necessary, but some values fail above cast (despite being in range). And appears to be random :(
            case let error as NSError: self = .codableError(CodableError(error: error))
            case let array as [Any]: self = .array(array.compactMap(UserInfoValue.init))
            case let dictionary as [String: Any]: self = .dictionary(dictionary.compactMapValues(UserInfoValue.init))
            default: self = .unknown(rawValue)
            }
        }
        
        init(from decoder: Decoder) throws
        {
            let container = try decoder.singleValueContainer()

            if
                let data = try? container.decode(Data.self),
                let error = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: data)
            {
                self = .error(error)
            }
            else if let codableError = try? container.decode(CodableError.self)
            {
                self = .codableError(codableError)
            }
            else if let string = try? container.decode(String.self)
            {
                self = .string(string)
            }
            else if let number = try? container.decode(Int.self)
            {
                self = .number(number)
            }
            else if let array = try? container.decode([UserInfoValue].self)
            {
                self = .array(array)
            }
            else if let dictionary = try? container.decode([String: UserInfoValue].self)
            {
                self = .dictionary(dictionary)
            }
            else
            {
                self = .unknown(nil)
            }
        }
        
        func encode(to encoder: Encoder) throws
        {
            var container = encoder.singleValueContainer()
            
            if let value = self.codableValue
            {
                try container.encode(value)
            }
            else
            {
                try container.encodeNil()
            }
        }
    }
}

struct CodableError: Codable
{
    var error: Error {
        return self.rawError ?? NSError(domain: self.errorDomain, code: self.errorCode, userInfo: self.userInfo ?? [:])
    }
    private var rawError: Error?
    
    private var errorDomain: String
    private var errorCode: Int
    private var userInfo: [String: Any]?
    
    private enum CodingKeys: String, CodingKey
    {
        case errorDomain
        case errorCode
        case legacyUserInfo = "userInfo"
        case errorUserInfo
    }

    init(error: Error)
    {
        self.rawError = error
        
        let nsError = error as NSError
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
        
        if !nsError.userInfo.isEmpty
        {
            self.userInfo = nsError.userInfo
        }
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Assume ALTServerError.errorDomain if no explicit domain provided.
        self.errorDomain = try container.decodeIfPresent(String.self, forKey: .errorDomain) ?? ALTServerError.errorDomain
        self.errorCode = try container.decode(Int.self, forKey: .errorCode)
        
        if let rawUserInfo = try container.decodeIfPresent([String: UserInfoValue].self, forKey: .errorUserInfo)
        {
            // Attempt decoding from .errorUserInfo first, because it will gracefully handle unknown user info values.
            
            // Copy ALTLocalized... values to NSLocalized... if provider is nil or if error is unrecognized.
            // This ensures we preserve error messages if receiving an unknown error.
            var userInfo = rawUserInfo.compactMapValues { $0.value }
            
            // Recognized == the provider returns value for NSLocalizedFailureReasonErrorKey, or error is ALTServerError.underlyingError.
            let provider = NSError.userInfoValueProvider(forDomain: self.errorDomain)
            let isRecognizedError = (
                provider?(self.error, NSLocalizedFailureReasonErrorKey) != nil ||
                (self.error._domain == ALTServerError.errorDomain && self.error._code == ALTServerError.underlyingError.rawValue)
            )
            
            if !isRecognizedError
            {
                // Error not recognized, so copy over NSLocalizedDescriptionKey and NSLocalizedFailureReasonErrorKey.
                userInfo[NSLocalizedDescriptionKey] = userInfo[ErrorUserInfoKey.altLocalizedDescription]
                userInfo[NSLocalizedFailureReasonErrorKey] = userInfo[ErrorUserInfoKey.altLocalizedFailureReason]
            }
            
            // Copy over NSLocalizedRecoverySuggestionErrorKey and NSDebugDescriptionErrorKey if provider returns nil.
            if provider?(self.error, NSLocalizedRecoverySuggestionErrorKey) == nil
            {
                userInfo[NSLocalizedRecoverySuggestionErrorKey] = userInfo[ErrorUserInfoKey.altLocalizedRecoverySuggestion]
            }
            
            if provider?(self.error, NSDebugDescriptionErrorKey) == nil
            {
                userInfo[NSDebugDescriptionErrorKey] = userInfo[ErrorUserInfoKey.altDebugDescription]
            }
            
            userInfo[ErrorUserInfoKey.altLocalizedDescription] = nil
            userInfo[ErrorUserInfoKey.altLocalizedFailureReason] = nil
            userInfo[ErrorUserInfoKey.altLocalizedRecoverySuggestion] = nil
            userInfo[ErrorUserInfoKey.altDebugDescription] = nil
            
            self.userInfo = userInfo
        }
        else if let rawUserInfo = try container.decodeIfPresent([String: UserInfoValue].self, forKey: .legacyUserInfo)
        {
            // Fall back to decoding .legacyUserInfo, which only supports String and NSError values.
            let userInfo = rawUserInfo.compactMapValues { $0.value }
            self.userInfo = userInfo
        }
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.errorDomain, forKey: .errorDomain)
        try container.encode(self.errorCode, forKey: .errorCode)
        
        let rawLegacyUserInfo = self.userInfo?.compactMapValues { (value) -> UserInfoValue? in
            // .legacyUserInfo only supports String and NSError values.
            switch value
            {
            case let string as String: return .string(string)
            case let error as NSError: return .error(error) // Must use .error, not .codableError for backwards compatibility.
            default: return nil
            }
        }
        try container.encodeIfPresent(rawLegacyUserInfo, forKey: .legacyUserInfo)
        
        let nsError = self.error as NSError
        
        var userInfo = self.userInfo ?? [:]
        userInfo[ErrorUserInfoKey.altLocalizedDescription] = nsError.localizedDescription
        userInfo[ErrorUserInfoKey.altLocalizedFailureReason] = nsError.localizedFailureReason
        userInfo[ErrorUserInfoKey.altLocalizedRecoverySuggestion] = nsError.localizedRecoverySuggestion
        userInfo[ErrorUserInfoKey.altDebugDescription] = nsError.localizedDebugDescription
        
        // No need to use alternate key. This is a no-op if userInfo already contains localizedFailure,
        // but it caches the UserInfoProvider value if one exists.
        userInfo[NSLocalizedFailureErrorKey] = nsError.localizedFailure
        
        let rawUserInfo = userInfo.compactMapValues { UserInfoValue($0) }
        try container.encodeIfPresent(rawUserInfo, forKey: .errorUserInfo)
    }
}
