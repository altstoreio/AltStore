//
//  Logger+AltJIT.swift
//  AltJIT
//
//  Created by Riley Testut on 8/29/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import OSLog

public extension Logger
{
    static let altjitSubsystem = Bundle.main.bundleIdentifier!
    
    static let main = Logger(subsystem: altjitSubsystem, category: "AltJIT")
}
