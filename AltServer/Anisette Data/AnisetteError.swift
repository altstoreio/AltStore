//
//  AnisetteError.swift
//  AltServer
//
//  Created by Riley Testut on 9/13/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

extension AnisetteError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = AnisetteError
        
        case aosKitFailure
        case missingValue
        case unsupportedOperatingSystem
        case invalidServerResponse
    }
    
    static func aosKitFailure(file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .aosKitFailure, sourceFile: file, sourceLine: line)
    }
    
    static func missingValue(_ value: String?, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .missingValue, value: value, sourceFile: file, sourceLine: line)
    }
    
    static func unsupportedOperatingSystem(file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .unsupportedOperatingSystem, sourceFile: file, sourceLine: line)
    }
    
    static func invalidServerResponse(_ value: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .invalidServerResponse, value: value, sourceFile: file, sourceLine: line)
    }
}

struct AnisetteError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var value: String?
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .aosKitFailure: return NSLocalizedString("AltServer could not retrieve anisette data from AOSKit.", comment: "")
        case .missingValue:
            let valueName = self.value.map { "anisette data value “\($0)”" } ?? NSLocalizedString("anisette data values.", comment: "")
            return String(format: NSLocalizedString("AltServer could not retrieve %@.", comment: ""), valueName)
            
        case .unsupportedOperatingSystem:
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion.stringValue
            return String(format: NSLocalizedString("macOS %@ does not provide anisette data to AltServer.", comment: ""), osVersion)
            
        case .invalidServerResponse:
            guard let value = self.value else { return NSLocalizedString("The anisette server returned an invalid response.", comment: "") }
            return String(format: NSLocalizedString("The anisette server did not return a value for “%@”.", comment: ""), value)
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .aosKitFailure, .missingValue, .unsupportedOperatingSystem:
            let bundleID = Bundle.main.bundleIdentifier ?? "com.rileytestut.AltServer"
            return String(format: NSLocalizedString("Run an anisette server, then tell AltServer to use it:\n\ndefaults write %@ AnisetteServerURL <url>", comment: ""), bundleID)
            
        case .invalidServerResponse:
            return NSLocalizedString("Make sure AltServer's AnisetteServerURL points to a working anisette server, then try again.", comment: "")
        }
    }
}
