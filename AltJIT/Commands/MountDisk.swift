//
//  MountDisk.swift
//  AltPackage
//
//  Created by Riley Testut on 8/31/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import OSLog

import ArgumentParser

typealias MountError = MountErrorCode.Error
enum MountErrorCode: Int, ALTErrorEnum
{
    case alreadyMounted
    
    var errorFailureReason: String {
        switch self
        {
        case .alreadyMounted: return NSLocalizedString("A personalized Developer Disk is already mounted.", comment: "")
        }
    }
}

struct MountDisk: PythonCommand
{
    static let configuration = CommandConfiguration(commandName: "mount", abstract: "Mount a personalized developer disk image onto an iOS device.")
    
    @Option(help: "The iOS device's UDID.")
    var udid: String
    
    // PythonCommand
    var pythonPath: String?
    
    mutating func run() async throws
    {
        do
        {
            print("Mounting personalized developer disk...")
            
            try await self.prepare()
            
            let output = try await Process.launchAndWait(.python3, arguments: ["-m", "pymobiledevice3", "mounter", "auto-mount", "--udid", self.udid])
            if !output.contains("DeveloperDiskImage")
            {
                throw ProcessError.unexpectedOutput(executableURL: .python3, output: output)
            }
            
            if output.contains("already mounted")
            {
                throw MountError(.alreadyMounted)
            }
            
            print("✅ Successfully mounted personalized Developer Disk!")
        }
        catch let error as MountError where error.code == .alreadyMounted
        {
            // Prepend ⚠️ since this is not really an error.
            let localizedDescription = "⚠️ " + error.localizedDescription
            print(localizedDescription)
            
            throw ExitCode.success
        }
        catch
        {
            // Output failure message first before error.
            print("❌ Unable to mount personalized Developer Disk.")
            print(error.localizedDescription)
            
            throw ExitCode.failure
        }
    }
}
