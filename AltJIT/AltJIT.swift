//
//  AltJIT.swift
//  AltJIT
//
//  Created by Riley Testut on 8/29/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import OSLog
import ArgumentParser

@main
struct AltJIT: AsyncParsableCommand
{
    static let configuration = CommandConfiguration(commandName: "altjit", 
                                                    abstract: "Enable JIT for sideloaded apps.",
                                                    subcommands: [EnableJIT.self, MountDisk.self])
}
