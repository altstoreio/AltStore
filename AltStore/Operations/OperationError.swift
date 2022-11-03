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
    case timedOut
    
    case notAuthenticated
    case appNotFound
    
    case unknownUDID
    
    case invalidApp
    case invalidParameters
    
    case maximumAppIDLimitReached(application: ALTApplication, requiredAppIDs: Int, availableAppIDs: Int, nextExpirationDate: Date)
    
    case noSources
    
    case openAppFailed(name: String)
    case missingAppGroup
    
    case noDevice
    case createService(name: String)
    case getFromDevice(name: String)
    case setArgument(name: String)
    case afc
    case install
    case uninstall
    case lookupApps
    case detach
    case functionArguments
    case profileInstall
    case noConnection
    
    var failureReason: String? {
        switch self {
        case .unknown: return NSLocalizedString("An unknown error occured.", comment: "")
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .appNotFound: return NSLocalizedString("App not found.", comment: "")
        case .unknownUDID: return NSLocalizedString("Unknown device UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .noSources: return NSLocalizedString("There are no AltStore sources.", comment: "")
        case .openAppFailed(let name): return String(format: NSLocalizedString("AltStore was denied permission to launch %@.", comment: ""), name)
        case .missingAppGroup: return NSLocalizedString("AltStore's shared app group could not be found.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")
        case .noDevice: return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .createService(let name): return String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
        case .getFromDevice(let name): return String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
        case .setArgument(let name): return String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
        case .afc: return NSLocalizedString("AFC was unable to manage files on the device", comment: "")
        case .install: return NSLocalizedString("Unable to install the app from the staging directory", comment: "")
        case .uninstall: return NSLocalizedString("Unable to uninstall the app", comment: "")
        case .lookupApps: return NSLocalizedString("Unable to fetch apps from the device", comment: "")
        case .detach: return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .functionArguments: return NSLocalizedString("A function was passed invalid arguments", comment: "")
        case .profileInstall: return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .noConnection: return NSLocalizedString("Unable to connect to the device, make sure Wireguard is enabled and you're connected to WiFi", comment: "")
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

func minimuxer_to_operation(code: Int32) -> OperationError {
    switch code {
    case -1:
        return OperationError.noDevice
    case -2:
        return OperationError.createService(name: "debug")
    case -3:
        return OperationError.createService(name: "instproxy")
    case -4:
        return OperationError.getFromDevice(name: "installed apps")
    case -5:
        return OperationError.getFromDevice(name: "path to the app")
    case -6:
        return OperationError.getFromDevice(name: "bundle path")
    case -7:
        return OperationError.setArgument(name: "max packet")
    case -8:
        return OperationError.setArgument(name: "working directory")
    case -9:
        return OperationError.setArgument(name: "argv")
    case -10:
        return OperationError.getFromDevice(name: "launch success")
    case -11:
        return OperationError.detach
    case -12:
        return OperationError.functionArguments
    case -13:
        return OperationError.createService(name: "AFC")
    case -14:
        return OperationError.afc
    case -15:
        return OperationError.install
    case -16:
        return OperationError.uninstall
    case -17:
        return OperationError.createService(name: "misagent")
    case -18:
        return OperationError.profileInstall
    case -19:
        return OperationError.profileInstall
    case -20:
        return OperationError.noConnection
    default:
        return OperationError.unknown
    }
}
