//
//  AnisetteServerError.swift
//  AltStore
//
//  Created by Caroline Moore on 9/3/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

extension AnisetteServerError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = AnisetteServerError

        case unavailable = 0
        case invalidServer = 1
        case invalidResponse = 2
    }
    
    static func unavailable(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteServerError {
        AnisetteServerError(code: .unavailable, serverURL: serverURL, underlyingError: underlyingError, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }
    
    static func invalidServer(file: String = #fileID, line: UInt = #line) -> AnisetteServerError {
        AnisetteServerError(code: .invalidServer, sourceFile: file, sourceLine: line)
    }
    
    static func invalidResponse(serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, file: String = #fileID, line: UInt = #line) -> AnisetteServerError {
        AnisetteServerError(code: .invalidResponse, serverURL: serverURL, underlyingError: underlyingError, debugDescription: debugDescription, sourceFile: file, sourceLine: line)
    }
}

struct AnisetteServerError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var serverURL: URL?
    
    // The transport or decoding error we translated, kept for the error log's detail view.
    @UserInfoValue(key: NSUnderlyingErrorKey)
    var networkUnderlyingError: NSError? = nil
    
    // Technical detail like the server's own error message or an HTTP status code.
    @UserInfoValue(key: NSDebugDescriptionErrorKey)
    var serverDebugDescription: String? = nil
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    fileprivate init(code: Code, serverURL: URL? = nil, underlyingError: Error? = nil, debugDescription: String? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil)
    {
        self.code = code
        self.serverURL = serverURL
        self.networkUnderlyingError = underlyingError.map { $0 as NSError }
        self.serverDebugDescription = debugDescription
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }
    
    private var serverName: String? {
        guard let serverURL else { return nil }
        return UserDefaults.standard.anisetteServers?.first { $0.url == serverURL }?.name ?? serverURL.host
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unavailable:
            if let serverName = self.serverName
            {
                return String(format: NSLocalizedString("The remote AltServer “%@” is currently unavailable.", comment: ""), serverName)
            }
            else
            {
                return NSLocalizedString("Your remote AltServer is currently unavailable.", comment: "")
            }
            
        case .invalidServer: return NSLocalizedString("The URL doesn’t point to a valid remote AltServer.", comment: "")
        case .invalidResponse:
            if let serverName = self.serverName
            {
                return String(format: NSLocalizedString("The remote AltServer “%@” sent an invalid response.", comment: ""), serverName)
            }
            else
            {
                return NSLocalizedString("Your remote AltServer sent an invalid response.", comment: "")
            }
        }
    }

    var recoverySuggestion: String? {
        switch self.code
        {
        case .unavailable, .invalidResponse: return NSLocalizedString("Try again in a few minutes, or choose a different server in AltStore’s settings.", comment: "")
        case .invalidServer: return NSLocalizedString("Make sure the URL points to a valid remote AltServer and try again.", comment: "")
        }
    }
}
