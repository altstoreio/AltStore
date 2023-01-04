//
//  OSLog+SideStore.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/16/22.
//  Copyright © 2022 SideStore. All rights reserved.
//

import Foundation
import OSLog

public let customLog = OSLog(subsystem: "org.sidestore.sidestore",
                      category: "ios")


public extension OSLog {
    /// Error logger extension
    /// - Parameters:
    ///   - message: String or format string
    ///   - args: optional args for format string
    @inlinable
    static func error(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .error, args)
    }
    
    /// Info logger extension
    /// - Parameters:
    ///   - message: String or format string
    ///   - args: optional args for format string
    @inlinable
    static func info(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .info, args)
    }
    
    /// Debug logger extension
    /// - Parameters:
    ///   - message: String or format string
    ///   - args: optional args for format string
    @inlinable
    static func debug(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .debug, args)
    }
}

// TODO: Add file,line,function to messages? -- @JoeMatt

/// Error logger convenience method for SideStore logging
/// - Parameters:
///   - message: String or format string
///   - args: optional args for format string
@inlinable
public func ELOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.error(message, args)
}

/// Info logger convenience method for SideStore logging
/// - Parameters:
///   - message: String or format string
///   - args: optional args for format string
@inlinable
public func ILOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.info(message, args)
}

/// Debug logger convenience method for SideStore logging
/// - Parameters:
///   - message: String or format string
///   - args: optional args for format string
@inlinable
public func DLOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.debug(message, args)
}

// mark: Helpers
