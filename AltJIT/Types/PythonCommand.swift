//
//  PythonCommand.swift
//  AltJIT
//
//  Created by Riley Testut on 9/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import ArgumentParser

protocol PythonCommand: AsyncParsableCommand
{
    var pythonPath: String? { get set }
}

extension PythonCommand
{
    var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        if let pythonPath
        {
            environment["PYTHONPATH"] = pythonPath
        }
        
        return environment
    }
    
    mutating func prepare() async throws
    {
        let pythonPath = try await self.readPythonPath()
        self.pythonPath = pythonPath.path(percentEncoded: false)
    }
}

private extension PythonCommand
{
    func readPythonPath() async throws -> URL
    {
        let processOutput: String
        
        do
        {
            processOutput = try await Process.launchAndWait(.python3, arguments: ["-m", "site", "--user-site"])
        }
        catch let error as ProcessError where error.exitCode == 2
        {
            // Ignore exit code 2.
            guard let output = error.output else { throw error }
            processOutput = output
        }
        
        let sanitizedOutput = processOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let pythonURL = URL(filePath: sanitizedOutput)
        return pythonURL
    }
}
