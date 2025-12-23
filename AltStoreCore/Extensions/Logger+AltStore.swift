//
//  Logger+AltStore.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

@_exported import OSLog

public extension Logger
{
    static let altstoreSubsystem = "com.rileytestut.AltStore" // Hardcoded because Bundle.main.bundleIdentifier is different for every user
    
    static let main = Logger(subsystem: altstoreSubsystem, category: "Main")
    static let sideload = Logger(subsystem: altstoreSubsystem, category: "Sideload")
    static let altjit = Logger(subsystem: altstoreSubsystem, category: "AltJIT")
    
    static let fugu14 = Logger(subsystem: altstoreSubsystem, category: "Fugu14")
}

@available(iOS 15, *)
public extension OSLogEntryLog.Level
{
    var localizedName: String {
        switch self
        {
        case .undefined: return NSLocalizedString("Undefined", bundle: Bundle(for: PatreonAPI.self), comment: "")
        case .debug: return NSLocalizedString("Debug", bundle: Bundle(for: PatreonAPI.self), comment: "")
        case .info: return NSLocalizedString("Info", bundle: Bundle(for: PatreonAPI.self), comment: "")
        case .notice: return NSLocalizedString("Notice", bundle: Bundle(for: PatreonAPI.self), comment: "")
        case .error: return NSLocalizedString("Error", bundle: Bundle(for: PatreonAPI.self), comment: "")
        case .fault: return NSLocalizedString("Fault", bundle: Bundle(for: PatreonAPI.self), comment: "")
        @unknown default: return NSLocalizedString("Unknown", bundle: Bundle(for: PatreonAPI.self), comment: "")
        }
    }
}
