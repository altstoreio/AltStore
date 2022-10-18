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
        case unknown
        case unknownResult
        case cancelled
        case timedOut
        case notAuthenticated
        case appNotFound
        case unknownUDID
        case invalidApp
        case invalidParameters
        case maximumAppIDLimitReached
        case noSources
        case openAppFailed
        case missingAppGroup
        
        /* Connection */
        case serverNotFound
        case connectionFailed
        case connectionDropped
    }
    
    static let unknownResult: OperationError = .init(code: .unknownResult)
    static let cancelled: OperationError = .init(code: .cancelled)
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
    
    static func unknown(file: String = #fileID, line: UInt = #line, function: String = #function) -> OperationError {
        OperationError(code: .unknown, sourceFile: file, sourceLine: line, sourceFunction: function)
    }
    
    static func appNotFound(name: String?) -> OperationError { OperationError(code: .appNotFound, appName: name) }
    static func openAppFailed(name: String) -> OperationError { OperationError(code: .openAppFailed, appName: name) }
    
    static func maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date) -> OperationError {
        OperationError(code: .maximumAppIDLimitReached, appName: appName, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
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
    var sourceFunction: String?
    
    private init(code: Code, appName: String? = nil, requiredAppIDs: Int? = nil, availableAppIDs: Int? = nil, expirationDate: Date? = nil,
                 sourceFile: String? = nil, sourceLine: UInt? = nil, sourceFunction: String? = nil)
    {
        self.code = code
        self.appName = appName
        self.requiredAppIDs = requiredAppIDs
        self.availableAppIDs = availableAppIDs
        self.expirationDate = expirationDate
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        self.sourceFunction = sourceFunction
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown:
            var failureReason = NSLocalizedString("An unknown error occured.", comment: "")
            guard let sourceFile, let sourceLine, let sourceFunction else { return failureReason }
            
            failureReason += " (\(sourceFile) \(sourceFunction) line \(sourceLine))"
            return failureReason
            
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .appNotFound: return NSLocalizedString("App not found.", comment: "")
        case .unknownUDID: return NSLocalizedString("Unknown device UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .noSources: return NSLocalizedString("There are no AltStore sources.", comment: "")
        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("the app", comment: "")
            return String(format: NSLocalizedString("AltStore was denied permission to launch %@.", comment: ""), appName)
            
        case .missingAppGroup: return NSLocalizedString("AltStore's shared app group could not be found.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")

        case .serverNotFound: return NSLocalizedString("Could not find AltServer.", comment: "")
        case .connectionFailed: return NSLocalizedString("Could not connect to AltServer.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .maximumAppIDLimitReached:
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            guard let appName = self.appName, let requiredAppIDs = self.requiredAppIDs, let availableAppIDs = self.availableAppIDs, let date = self.expirationDate else { return baseMessage }
            
            let message: String
            
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
                message = prefixMessage + " " + baseMessage
            }
            else
            {
                let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
                
                let dateComponentsFormatter = DateComponentsFormatter()
                dateComponentsFormatter.maximumUnitCount = 1
                dateComponentsFormatter.unitsStyle = .full
                
                let remainingTime = dateComponentsFormatter.string(from: dateComponents)!
                
                let remainingTimeMessage = String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)
                message = baseMessage + " " + remainingTimeMessage
            }
            
            return message
            
        default: return nil
        }
    }
}
