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
    case maximumAppIDLimitReached(Date)
    
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
            
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self
        {
        case .maximumAppIDLimitReached(let date):
            let remainingTime: String
            
            let numberOfDays = date.numberOfCalendarDays(since: Date())
            switch numberOfDays {
            case 0:
                let components = Calendar.current.dateComponents([.hour], from: Date(), to: date)
                let numberOfHours = components.hour!
                
                switch numberOfHours
                {
                case 1: remainingTime = NSLocalizedString("1 hour", comment: "")
                default: remainingTime = String(format: NSLocalizedString("%@ hours", comment: ""), NSNumber(value: numberOfHours))
                }
                
            case 1: remainingTime = NSLocalizedString("1 day", comment: "")
            default: remainingTime = String(format: NSLocalizedString("%@ days", comment: ""), NSNumber(value: numberOfDays))
            }
            
            let message = String(format: NSLocalizedString("Delete sideloaded apps to free up App ID slots. You can register another App ID in %@.", comment: ""), remainingTime)
            return message
            
        default: return nil
        }
    }
}
