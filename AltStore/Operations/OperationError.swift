//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign
import AltStoreCore

extension OperationError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = OperationError
        
        /* General */
        case unknown = 1000
        case unknownResult = 1001
        // case cancelled = 1002
        case timedOut = 1003
        case notAuthenticated = 1004
        case appNotFound = 1005
        case unknownUDID = 1006
        case invalidApp = 1007
        case invalidParameters = 1008
        case maximumAppIDLimitReached = 1009
        case noSources = 1010
        case openAppFailed = 1011
        case missingAppGroup = 1012
        case forbidden = 1013
        
        /* Connection */
        case serverNotFound = 1200
        case connectionFailed = 1201
        case connectionDropped = 1202
    }
    
    static var cancelled: CancellationError { CancellationError() }
    
    static let unknownResult: OperationError = .init(code: .unknownResult)
    static let timedOut: OperationError = .init(code: .timedOut)
    static let notAuthenticated: OperationError = .init(code: .notAuthenticated)
    static let unknownUDID: OperationError = .init(code: .unknownUDID)
    static let invalidApp: OperationError = .init(code: .invalidApp)
    static let invalidParameters: OperationError = .init(code: .invalidParameters)
    static let noSources: OperationError = .init(code: .noSources)
    static let missingAppGroup: OperationError = .init(code: .missingAppGroup)
    
    static let serverNotFound: OperationError = .init(code: .serverNotFound)
    static let connectionFailed: OperationError = .init(code: .connectionFailed)
    static let connectionDropped: OperationError = .init(code: .connectionDropped)
    
    static func unknown(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .unknown, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }
    
    static func appNotFound(name: String?) -> OperationError { OperationError(code: .appNotFound, appName: name) }
    static func openAppFailed(name: String) -> OperationError { OperationError(code: .openAppFailed, appName: name) }
    
    static func maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date) -> OperationError {
        OperationError(code: .maximumAppIDLimitReached, appName: appName, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
    }
    
    static func forbidden(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .forbidden, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }
}

struct OperationError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    var appName: String?
    var requiredAppIDs: Int?
    var availableAppIDs: Int?
    var expirationDate: Date?
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    private init(code: Code, failureReason: String? = nil, appName: String? = nil, requiredAppIDs: Int? = nil, availableAppIDs: Int? = nil, expirationDate: Date? = nil,
                 sourceFile: String? = nil, sourceLine: UInt? = nil)
    {
        self.code = code
        self._failureReason = failureReason
        
        self.appName = appName
        self.requiredAppIDs = requiredAppIDs
        self.availableAppIDs = availableAppIDs
        self.expirationDate = expirationDate
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown:
            var failureReason = self._failureReason ?? NSLocalizedString("An unknown error occured.", comment: "")
            guard let sourceFile, let sourceLine else { return failureReason }
            
            failureReason += " (\(sourceFile) line \(sourceLine))"
            return failureReason
            
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .unknownUDID: return NSLocalizedString("AltStore could not determine this device's UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is in an invalid format.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("You cannot register more than 10 App IDs within a 7 day period.", comment: "")
        case .noSources: return NSLocalizedString("There are no AltStore sources.", comment: "")
        case .missingAppGroup: return NSLocalizedString("AltStore's shared app group could not be accessed.", comment: "")
        case .forbidden:
            guard let failureReason = self._failureReason else { return NSLocalizedString("The operation is forbidden.", comment: "") }
            return failureReason

        case .appNotFound:
            let appName = self.appName ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ could not be found.", comment: ""), appName)

        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("the app", comment: "")
            return String(format: NSLocalizedString("AltStore was denied permission to launch %@.", comment: ""), appName)

        case .serverNotFound: return NSLocalizedString("AltServer could not be found.", comment: "")
        case .connectionFailed: return NSLocalizedString("A connection to AltServer could not be established.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        }
    }
    private var _failureReason: String?
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .serverNotFound: return NSLocalizedString("Make sure you're on the same WiFi network as a computer running AltServer, or try connecting this device to your computer via USB.", comment: "")
        case .maximumAppIDLimitReached:
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            guard let appName = self.appName, let requiredAppIDs = self.requiredAppIDs, let availableAppIDs = self.availableAppIDs, let date = self.expirationDate else { return baseMessage }
            
            var message: String = ""
            
            if requiredAppIDs > 1
            {
                let availableText: String
                
                switch availableAppIDs
                {
                case 0: availableText = NSLocalizedString("none are available", comment: "")
                case 1: availableText = NSLocalizedString("only 1 is available", comment: "")
                default: availableText = String(format: NSLocalizedString("only %@ are available", comment: ""), NSNumber(value: availableAppIDs))
                }
                
                let prefixMessage = String(format: NSLocalizedString("%@ requires %@ App IDs, but %@.", comment: ""), appName, NSNumber(value: requiredAppIDs), availableText)
                message = prefixMessage + " " + baseMessage + "\n\n"
            }
            else
            {
                message = baseMessage + " "
            }
            
            let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
            
            let dateComponentsFormatter = DateComponentsFormatter()
            dateComponentsFormatter.maximumUnitCount = 1
            dateComponentsFormatter.unitsStyle = .full
            
            let remainingTime = dateComponentsFormatter.string(from: dateComponents)!
            
            let remainingTimeMessage = String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)
            message += remainingTimeMessage
            
            return message
            
        default: return nil
        }
    }
}
