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
        case localAnisetteFailed
        case remoteServerUnavailable
        case remoteServerInvalidResponse
        case provisioningFailed
    }
    
    static func aosKitFailure(file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .aosKitFailure, sourceFile: file, sourceLine: line)
    }
    
    static func missingValue(_ value: String?, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .missingValue, value: value, sourceFile: file, sourceLine: line)
    }
    
    static func localAnisetteFailed(underlyingError: Error, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .localAnisetteFailed, anisetteUnderlyingError: underlyingError as NSError, sourceFile: file, sourceLine: line)
    }
    
    static func remoteServerUnavailable(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .remoteServerUnavailable, serverURL: serverURL, anisetteUnderlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }
    
    static func remoteServerInvalidResponse(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .remoteServerInvalidResponse, serverURL: serverURL, anisetteUnderlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }
    
    static func provisioningFailed(underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .provisioningFailed, anisetteUnderlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }
}

struct AnisetteError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var value: String?
    
    @UserInfoValue
    var serverURL: URL?
    
    @UserInfoValue(key: NSUnderlyingErrorKey)
    var anisetteUnderlyingError: NSError? = nil
    
    @UserInfoValue(key: NSDebugDescriptionErrorKey)
    var debugDescription: String? = nil
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .aosKitFailure: return NSLocalizedString("AltServer could not retrieve anisette data from AOSKit.", comment: "")
        case .missingValue:
            let valueName = self.value.map { "anisette data value “\($0)”" } ?? NSLocalizedString("anisette data values.", comment: "")
            return String(format: NSLocalizedString("AltServer could not retrieve %@.", comment: ""), valueName)
            
        case .localAnisetteFailed:
            var baseMessage = NSLocalizedString("AltServer could not generate anisette data locally.", comment: "")
            
            if let underlyingError = self.anisetteUnderlyingError
            {
                baseMessage += " " + underlyingError.localizedDescription
            }
            
            return baseMessage
            
        case .remoteServerUnavailable:
            guard let serverName = self.serverURL?.host else { return NSLocalizedString("No anisette server is currently available.", comment: "") }
            return String(format: NSLocalizedString("The anisette server “%@” is currently unavailable.", comment: ""), serverName)
            
        case .remoteServerInvalidResponse:
            guard let serverName = self.serverURL?.host else { return NSLocalizedString("The anisette server sent an invalid response.", comment: "") }
            return String(format: NSLocalizedString("The anisette server “%@” sent an invalid response.", comment: ""), serverName)
            
        case .provisioningFailed: return NSLocalizedString("AltServer could not provision anisette data with Apple's servers.", comment: "")
        }
    }
}
