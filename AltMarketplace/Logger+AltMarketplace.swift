//
//  Logger+AltMarketplace.swift
//  AltMarketplace
//
//  Created by Riley Testut on 2/23/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

@_exported import OSLog

public extension Logger
{
    static let altmarketplaceSubsystem = "com.rileytestut.AltStore.AltMarketplace" // Hardcoded because Bundle.main.bundleIdentifier is different for every user
    
    static let main = Logger(subsystem: altmarketplaceSubsystem, category: "Main")
}
