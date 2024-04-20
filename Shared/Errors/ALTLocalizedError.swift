//
//  ALTLocalizedError.swift
//  AltStore
//
//  Created by Riley Testut on 10/14/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

#if !ALTJIT
import AltSign
#endif

public let ALTLocalizedTitleErrorKey = "ALTLocalizedTitle"
public let ALTLocalizedDescriptionKey = "ALTLocalizedDescription"

public protocol ALTLocalizedError<Code>: LocalizedError, CustomNSError, CustomStringConvertible
{
    associatedtype Code: ALTErrorCode

    var code: Code { get }
    var errorFailureReason: String { get }
    
    var errorTitle: String? { get set }
    var errorFailure: String? { get set }
    
    var sourceFile: String? { get set }
    var sourceLine: UInt? { get set }
}

public extension ALTLocalizedError
{
    var sourceFile: String? {
        get { nil }
        set {}
    }
    
    var sourceLine: UInt? {
        get { nil }
        set {}
    }
}

public protocol ALTErrorCode: RawRepresentable where RawValue == Int
{
    associatedtype Error: ALTLocalizedError where Error.Code == Self
    
    static var errorDomain: String { get } // Optional
}

public protocol ALTErrorEnum: ALTErrorCode
{
    associatedtype Error = DefaultLocalizedError<Self>
    
    var errorFailureReason: String { get }
}

/// LocalizedError & CustomNSError & CustomStringConvertible
public extension ALTLocalizedError
{
    var errorCode: Int { self.code.rawValue }
    
    var errorDescription: String? {
        guard (self as NSError).localizedFailure == nil else {
            // Error has localizedFailure, so return nil to construct localizedDescription from it + localizedFailureReason.
            return nil
        }
        
        // Otherwise, return failureReason for localizedDescription to avoid system prepending "Operation Failed" message.
        return self.failureReason
    }
    
    var failureReason: String? {
        return self.errorFailureReason
    }
    
    var errorUserInfo: [String : Any] {
        var userInfo: [String: Any?] = [
            NSLocalizedFailureErrorKey: self.errorFailure,
            ALTLocalizedTitleErrorKey: self.errorTitle,
            ALTSourceFileErrorKey: self.sourceFile,
            ALTSourceLineErrorKey: self.sourceLine,
        ]
        
        userInfo.merge(self.userInfoValues) { (_, new) in new }
        
        return userInfo.compactMapValues { $0 }
    }
    
    var description: String {
        let description = "\(self.localizedErrorCode) “\(self.localizedDescription)”"
        return description
    }
}

/// Default Implementations
public extension ALTLocalizedError where Code: ALTErrorEnum
{
    static var errorDomain: String {
        return Code.errorDomain
    }
    
    // ALTErrorEnum Codes provide their failure reason directly.
    var errorFailureReason: String {
        return self.code.errorFailureReason
    }
}

/// Default Implementations
public extension ALTErrorCode
{
    static var errorDomain: String {
        let typeName = String(reflecting: Self.self) // "\(Self.self)" doesn't include module name, but String(reflecting:) does.
        let errorDomain = typeName.replacingOccurrences(of: "ErrorCode", with: "Error").replacingOccurrences(of: "Error.Code", with: "Error")
        return errorDomain
    }
}

public extension ALTLocalizedError
{
    // Allows us to initialize errors with localizedTitle + localizedFailure
    // while still using the error's custom initializer at callsite.
    init(_ error: Self, localizedTitle: String? = nil, localizedFailure: String? = nil)
    {
        self = error
        
        if let localizedTitle
        {
            self.errorTitle = localizedTitle
        }
        
        if let localizedFailure
        {
            self.errorFailure = localizedFailure
        }
    }
}

private extension ALTLocalizedError
{
    var userInfoValues: [(String, Any)] {
        let userInfoValues = Mirror(reflecting: self).children.compactMap { (label, value) -> (String, Any)? in
            guard let userInfoValue = value as? any UserInfoValueProtocol,
                  let key: any StringProtocol = userInfoValue.key ?? label?.dropFirst() // Remove leading underscore
            else { return nil }

            return (String(key), userInfoValue.wrappedValue)
        }
        
        return userInfoValues
    }
}

public struct DefaultLocalizedError<Code: ALTErrorEnum>: ALTLocalizedError
{
    public let code: Code

    public var errorTitle: String?
    public var errorFailure: String?
    public var sourceFile: String?
    public var sourceLine: UInt?

    public init(_ code: Code, localizedTitle: String? = nil, localizedFailure: String? = nil, sourceFile: String? = #fileID, sourceLine: UInt? = #line)
    {
        self.code = code
        self.errorTitle = localizedTitle
        self.errorFailure = localizedFailure
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }
}

/// Custom Operators
/// These allow us to pattern match ALTErrorCodes against arbitrary errors via ~ prefix.
prefix operator ~
public prefix func ~<Code: ALTErrorCode>(expression: Code) -> NSError
{
    let nsError = NSError(domain: Code.errorDomain, code: expression.rawValue)
    return nsError
}

public func ~=(pattern: any Swift.Error, value: any Swift.Error) -> Bool
{
    let isMatch = pattern._domain == value._domain && pattern._code == value._code
    return isMatch
}

// These operators *should* allow us to match ALTErrorCodes against arbitrary errors,
// but they don't work as of iOS 16.1 and Swift 5.7.
//
//public func ~=<Error: ALTLocalizedError>(pattern: Error, value: Swift.Error) -> Bool
//{
//    let isMatch = pattern._domain == value._domain && pattern._code == value._code
//    return isMatch
//}
//
//public func ~=<Code: ALTErrorCode>(pattern: Code, value: Swift.Error) -> Bool
//{
//    let isMatch = Code.errorDomain == value._domain && pattern.rawValue == value._code
//    return isMatch
//}
