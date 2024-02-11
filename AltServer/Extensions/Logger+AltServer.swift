//
//  Logger+AltServer.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import OSLog

extension Logger
{
    static let altserverSubsystem = Bundle.main.bundleIdentifier!
    
    static let main = Logger(subsystem: altserverSubsystem, category: "AltServer")
}
