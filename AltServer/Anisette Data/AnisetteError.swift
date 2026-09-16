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

    static func remoteServerUnavailable(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .remoteServerUnavailable, serverURL: serverURL, underlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }

    static func remoteServerInvalidResponse(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .remoteServerInvalidResponse, serverURL: serverURL, underlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }

    static func provisioningFailed(underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteError {
        AnisetteError(code: .provisioningFailed, underlyingError: underlyingError.map { $0 as NSError }, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
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

    // The transport or decoding error we translated, kept for the error log's detail view.
    @UserInfoValue(key: NSUnderlyingErrorKey)
    var underlyingError: NSError? = nil

    // Technical detail like the server's own error message or an HTTP status code.
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

        case .remoteServerUnavailable:
            if let serverName = self.serverURL?.host
            {
                return String(format: NSLocalizedString("The anisette server “%@” is currently unavailable.", comment: ""), serverName)
            }
            else
            {
                return NSLocalizedString("No anisette server is currently available.", comment: "")
            }

        case .remoteServerInvalidResponse:
            if let serverName = self.serverURL?.host
            {
                return String(format: NSLocalizedString("The anisette server “%@” sent an invalid response.", comment: ""), serverName)
            }
            else
            {
                return NSLocalizedString("The anisette server sent an invalid response.", comment: "")
            }

        case .provisioningFailed: return NSLocalizedString("AltServer could not provision anisette data with Apple's servers.", comment: "")
        }
    }

    var recoverySuggestion: String? {
        switch self.code
        {
        case .aosKitFailure, .missingValue: return nil
        case .remoteServerUnavailable, .remoteServerInvalidResponse, .provisioningFailed:
            return NSLocalizedString("Try again in a few minutes. You can also choose a specific anisette server by running “defaults write com.rileytestut.AltServer AnisetteServerURL <url>” in Terminal.", comment: "")
        }
    }
}
