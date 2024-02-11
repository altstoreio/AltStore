//
//  Process+STPrivilegedTask.swift
//  AltServer
//
//  Created by Riley Testut on 8/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import Security
import OSLog

import STPrivilegedTask

extension Process
{
    class func runAsAdmin(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil) throws -> AuthorizationRef?
    {
        var launchPath = "/usr/bin/" + program
        if !FileManager.default.fileExists(atPath: launchPath)
        {
            launchPath = "/bin/" + program
        }
        
        if !FileManager.default.fileExists(atPath: launchPath)
        {
            launchPath = program
        }
        
        Logger.main.info("Launching admin process: \(launchPath, privacy: .public)")
        
        let task = STPrivilegedTask()
        task.launchPath = launchPath
        task.arguments = arguments
        task.freeAuthorizationWhenDone = false
        
        let errorCode: OSStatus
        
        if let authorization = authorization
        {
            errorCode = task.launch(withAuthorization: authorization)
        }
        else
        {
            errorCode = task.launch()
        }
        
        let executableURL = URL(fileURLWithPath: launchPath)
        guard errorCode == 0 else { throw ProcessError.failed(executableURL: executableURL, exitCode: errorCode, output: nil) }
        
        task.waitUntilExit()
        
        Logger.main.info("Admin process \(launchPath, privacy: .public) terminated with exit code \(task.terminationStatus, privacy: .public).")
        
        guard task.terminationStatus == 0 else {
            let executableURL = URL(fileURLWithPath: launchPath)
            
            let outputData = task.outputFileHandle.readDataToEndOfFile()
            if let outputString = String(data: outputData, encoding: .utf8), !outputString.isEmpty
            {
                throw ProcessError.failed(executableURL: executableURL, exitCode: task.terminationStatus, output: outputString)
            }
            else
            {
                throw ProcessError.failed(executableURL: executableURL, exitCode: task.terminationStatus, output: nil)
            }
        }
        
        return task.authorization
    }
}
