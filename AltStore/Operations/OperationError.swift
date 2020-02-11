//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

enum OperationError: LocalizedError
{
    case unknown
    case unknownResult
    case cancelled
    
    case notAuthenticated
    case appNotFound
    
    case unknownUDID
    
    case invalidApp
    case invalidParameters
    
    case iOSVersionNotSupported(ALTApplication)
    case sideloadingAppNotSupported(ALTApplication)
    case maximumAppIDLimitReached(application: ALTApplication, requiredAppIDs: Int, availableAppIDs: Int, nextExpirationDate: Date)
    
    case noSources
    
    var errorDescription: String? {
        switch self {
        case .unknown: return NSLocalizedString("An unknown error occured.", comment: "")
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .appNotFound: return NSLocalizedString("App not found.", comment: "")
        case .unknownUDID: return NSLocalizedString("Unknown device UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .noSources: return NSLocalizedString("There are no AltStore sources.", comment: "")
        case .iOSVersionNotSupported(let app):
            let name = app.name
            
            var version = "iOS \(app.minimumiOSVersion.majorVersion).\(app.minimumiOSVersion.minorVersion)"
            if app.minimumiOSVersion.patchVersion > 0
            {
                version += ".\(app.minimumiOSVersion.patchVersion)"
            }
            
            let localizedDescription = String(format: NSLocalizedString("%@ requires %@.", comment: ""), name, version)
            return localizedDescription
            
        case .sideloadingAppNotSupported(let app):
            let localizedDescription = String(format: NSLocalizedString("Sideloading “%@” Not Supported", comment: ""), app.name)
            return localizedDescription
            
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self
        {
        case .maximumAppIDLimitReached(let application, let requiredAppIDs, let availableAppIDs, let date):
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
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
                
                let prefixMessage = String(format: NSLocalizedString("%@ requires %@ App IDs, but %@.", comment: ""), application.name, NSNumber(value: requiredAppIDs), availableText)
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
