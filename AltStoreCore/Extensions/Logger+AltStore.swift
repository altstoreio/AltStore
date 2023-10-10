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
    static let altstoreSubsystem = Bundle.main.bundleIdentifier!
    
    static let main = Logger(subsystem: altstoreSubsystem, category: "Main")
    static let sideload = Logger(subsystem: altstoreSubsystem, category: "Sideload")
    
    static let fugu14 = Logger(subsystem: altstoreSubsystem, category: "Fugu14")
}

