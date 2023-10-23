//
//  EnableJIT.swift
//  AltPackage
//
//  Created by Riley Testut on 8/29/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import OSLog
import RegexBuilder

import ArgumentParser

struct EnableJIT: PythonCommand
{
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Enable JIT for a specific app on your device.")
    
    @Argument(help: "The name or PID of the app to enable JIT for.", transform: AppProcess.init)
    var process: AppProcess
    
    @Option(help: "Your iOS device's UDID.")
    var udid: String
    
    // PythonCommand
    var pythonPath: String?
    
    mutating func run() async throws
    {
        // Use local variables to fix "escaping autoclosure captures mutating self parameter" compiler error.
        let process = self.process
        let udid = self.udid        
        
        do
        {
            do
            {
                Logger.main.info("Enabling JIT for \(process, privacy: .private(mask: .hash)) on device \(udid, privacy: .private(mask: .hash))...")
                
                try await self.prepare()
                
                let rsdTunnel = try await self.startRSDTunnel()
                defer { rsdTunnel.process.terminate() }
                print("Connected to device \(self.udid)!", rsdTunnel)
                
                let port = try await self.startDebugServer(rsdTunnel: rsdTunnel)
                print("Started debugserver on port \(port).")
                
                print("Attaching debugger...")
                let lldb = try await self.attachDebugger(ipAddress: rsdTunnel.ipAddress, port: port)
                defer { lldb.terminate() }
                print("Attached debugger to \(process).")
                
                try await self.detachDebugger(lldb)
                print("Detached debugger from \(process).")
                
                print("✅ Successfully enabled JIT for \(process) on device \(udid)!")
            }
            catch let error as ProcessError
            {
                if let output = error.output
                {
                    print(output)
                }
                
                throw error
            }
        }
        catch
        {
            print("❌ Unable to enable JIT for \(process) on device \(udid).")
            print(error.localizedDescription)
            
            Logger.main.error("Failed to enable JIT for \(process, privacy: .private(mask: .hash)) on device \(udid, privacy: .private(mask: .hash)). \(error, privacy: .public)")
            
            throw ExitCode.failure
        }
    }
}

private extension EnableJIT
{
    func startRSDTunnel() async throws -> RemoteServiceDiscoveryTunnel
    {
        do
        {
            Logger.main.info("Starting RSD tunnel...")
            
            let process = try Process.launch(.python3, arguments: ["-u", "-m", "pymobiledevice3", "remote", "start-quic-tunnel", "--udid", self.udid], environment: self.processEnvironment)
            
            do
            {
                let rsdTunnel = try await withTimeout(seconds: 20) {
                    let regex = Regex {
                        "--rsd"
                        
                        OneOrMore(.whitespace)
                        
                        Capture {
                            OneOrMore(.anyGraphemeCluster)
                        }
                        
                        OneOrMore(.whitespace)
                        
                        TryCapture {
                            OneOrMore(.digit)
                        } transform: { match in
                            Int(match)
                        }
                    }
                    
                    for try await line in process.outputLines
                    {
                        if let match = line.firstMatch(of: regex)
                        {
                            let rsdTunnel = RemoteServiceDiscoveryTunnel(ipAddress: String(match.1), port: match.2, process: process)
                            return rsdTunnel
                        }
                    }
                    
                    throw ProcessError.unexpectedOutput(executableURL: .python3, output: process.output)
                }
                
                // MUST close standardOutput in order to stream output later.
                process.stopOutput()
                
                return rsdTunnel
            }
            catch is TimedOutError
            {
                process.terminate()
                
                let error = ProcessError.timedOut(executableURL: .python3, output: process.output)
                throw error
            }
            catch
            {
                process.terminate()
                throw error
            }
        }
        catch let error as NSError
        {
            let localizedFailure = NSLocalizedString("Could not connect to device \(self.udid).", comment: "")
            throw error.withLocalizedFailure(localizedFailure)
        }
    }
    
    func startDebugServer(rsdTunnel: RemoteServiceDiscoveryTunnel) async throws -> Int
    {
        do
        {
            Logger.main.info("Starting debugserver...")
            
            return try await withTimeout(seconds: 10) {
                let arguments = ["-u", "-m", "pymobiledevice3", "developer", "debugserver", "start-server"] + rsdTunnel.commandArguments
                
                let output = try await Process.launchAndWait(.python3, arguments: arguments, environment: self.processEnvironment)
                
                let port = Reference(Int.self)
                let regex = Regex {
                    "connect://"
                    
                    OneOrMore(.anyGraphemeCluster, .eager)
                    
                    ":"
                    
                    TryCapture(as: port) {
                        OneOrMore(.digit)
                    } transform: { match in
                        Int(match)
                    }
                }
                
                if let match = output.firstMatch(of: regex)
                {
                    return match[port]
                }
                
                throw ProcessError.unexpectedOutput(executableURL: .python3, output: output)
            }
        }
        catch let error as NSError
        {
            let localizedFailure = NSLocalizedString("Could not start debugserver on device \(self.udid).", comment: "")
            throw error.withLocalizedFailure(localizedFailure)
        }
    }
    
    func attachDebugger(ipAddress: String, port: Int) async throws -> Process
    {
        do
        {
            Logger.main.info("Attaching debugger...")
            
            let processID: Int
            
            switch self.process
            {
            case .pid(let pid): processID = pid
            case .name(let name):
                guard let pid = try await self.getPID(for: name) else { throw JITError.processNotRunning(self.process) }
                processID = pid
            }
            
            let process = try Process.launch(.lldb, environment: self.processEnvironment)
            
            do
            {
                try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                    
    //                // Throw error if program terminates.
    //                taskGroup.addTask {
    //                    try await withCheckedThrowingContinuation { continuation in
    //                        process.terminationHandler = { process in
    //                            Task {
    //                                // Should NEVER be called unless an error occurs.
    //                                continuation.resume(throwing: ProcessError.terminated(executableURL: .lldb, exitCode: process.terminationStatus, output: process.output))
    //                            }
    //                        }
    //                    }
    //                }
                    
                    taskGroup.addTask {
                        do
                        {
                            try await self.sendDebuggerCommand("platform select remote-ios", to: process, timeout: 5) {
                                ChoiceOf {
                                    "SDK Roots:"
                                    "unable to locate SDK"
                                }
                            }
                            
                            let ipAddress = "[\(ipAddress)]"
                            let connectCommand = "process connect connect://\(ipAddress):\(port)"
                            try await self.sendDebuggerCommand(connectCommand, to: process, timeout: 10)
                            
                            try await self.sendDebuggerCommand("settings set target.memory-module-load-level minimal", to: process, timeout: 5)
                            
                            let attachCommand = "attach -p \(processID)"
                            let failureMessage = "attach failed"
                            let output = try await self.sendDebuggerCommand(attachCommand, to: process, timeout: 120) {
                                
                                ChoiceOf {
                                    failureMessage
                                    
                                    Regex {
                                        "Process "
                                        OneOrMore(.digit)
                                        " stopped"
                                    }
                                }
                            }
                            
                            if output.contains(failureMessage)
                            {
                                throw ProcessError.failed(executableURL: .lldb, exitCode: -1, output: process.output)
                            }
                        }
                        catch is TimedOutError
                        {
                            let error = ProcessError.timedOut(executableURL: .lldb, output: process.output)
                            throw error
                        }
                    }
                    
                    // Wait until first child task returns
                    _ = try await taskGroup.next()!
                    
                    // Cancel remaining tasks
                    taskGroup.cancelAll()
                }
                
                return process
            }
            catch
            {
                process.terminate()
                throw error
            }
        }
        catch let error as NSError
        {
            let localizedFailure = String(format: NSLocalizedString("Could not attach debugger to %@.", comment: ""), self.process.description)
            throw error.withLocalizedFailure(localizedFailure)
        }
    }
    
    func detachDebugger(_ process: Process) async throws
    {
        do
        {
            Logger.main.info("Detaching debugger...")
            
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                
//                // Throw error if program terminates.
//                taskGroup.addTask {
//                    try await withCheckedThrowingContinuation { continuation in
//                        process.terminationHandler = { process in
//                            if process.terminationStatus == 0
//                            {
//                                continuation.resume()
//                            }
//                            else
//                            {
//                                continuation.resume(throwing: ProcessError.terminated(executableURL: .lldb, exitCode: process.terminationStatus, output: process.output))
//                            }
//                        }
//                    }
//                }
                
                taskGroup.addTask {
                    do
                    {
                        try await self.sendDebuggerCommand("c", to: process, timeout: 10) {
                            "Process "
                            OneOrMore(.digit)
                            " resuming"
                        }
                        
                        try await self.sendDebuggerCommand("detach", to: process, timeout: 10) {
                            "Process "
                            OneOrMore(.digit)
                            " detached"
                        }
                    }
                    catch is TimedOutError
                    {
                        let error = ProcessError.timedOut(executableURL: .lldb, output: process.output)
                        throw error
                    }
                }
                
                // Wait until first child task returns
                _ = try await taskGroup.next()!
                
                // Cancel remaining tasks
                taskGroup.cancelAll()
            }
        }
        catch let error as NSError
        {
            let localizedFailure = NSLocalizedString("Could not detach debugger from \(self.process).", comment: "")
            throw error.withLocalizedFailure(localizedFailure)
        }
    }
}

private extension EnableJIT
{
    func getPID(for name: String) async throws -> Int?
    {
        Logger.main.info("Retrieving PID for \(name, privacy: .private(mask: .hash))...")
        
        let arguments = ["-m", "pymobiledevice3", "processes", "pgrep", name, "--udid", self.udid]
        let output = try await Process.launchAndWait(.python3, arguments: arguments, environment: self.processEnvironment)
        
        let regex = Regex {
            "INFO"
            
            OneOrMore(.whitespace)
            
            TryCapture {
                OneOrMore(.digit)
            } transform: { match in
                Int(match)
            }
            
            OneOrMore(.whitespace)
            
            name
        }
        
        if let match = output.firstMatch(of: regex)
        {
            Logger.main.info("\(name, privacy: .private(mask: .hash)) PID is \(match.1)")
            return match.1
        }
        
        return nil
    }
    
    @discardableResult
    func sendDebuggerCommand(_ command: String, to process: Process, timeout: TimeInterval,
                             @RegexComponentBuilder regex: @escaping () -> (some RegexComponent<Substring>)? = { Optional<Regex<Substring>>.none }) async throws -> String
    {
        guard let inputPipe = process.standardInput as? Pipe else { preconditionFailure("`process` must have a Pipe as its standardInput") }
        defer {
            inputPipe.fileHandleForWriting.writeabilityHandler = nil
        }
        
        let initialOutput = process.output
        
        let data = (command + "\n").data(using: .utf8)! // Will always succeed.
        Logger.main.info("Sending lldb command: \(command, privacy: .public)")
        
        let output = try await withTimeout(seconds: timeout) {
            // Wait until process is ready to receive input.
            try await withCheckedThrowingContinuation { continuation in
                inputPipe.fileHandleForWriting.writeabilityHandler = { fileHandle in
                    inputPipe.fileHandleForWriting.writeabilityHandler = nil
                    
                    let result = Result { try fileHandle.write(contentsOf: data) }
                    continuation.resume(with: result)
                }
            }
            
            // Wait until we receive at least one line of output.
            for try await _ in process.outputLines
            {
                break
            }
            
            // Keep waiting until output doesn't change.
            // If regex is provided, we keep waiting until a match is found.
            var previousOutput = process.output
            while true
            {
                try await Task.sleep(for: .seconds(0.2))
                
                let output = process.output
                if output == previousOutput
                {
                    guard let regex = regex() else {
                        // No regex, so break as soon as output stops changing.
                        break
                    }
                    
                    if output.contains(regex)
                    {
                        // Found a match, so exit while loop.
                        break
                    }
                    else
                    {
                        // Output hasn't changed, but regex does not match (yet).
                        continue
                    }
                }
                
                previousOutput = output
            }
            
            return previousOutput
        }
        
        // Subtract initialOutput from output to get just this command's output.
        let commandOutput = output.replacingOccurrences(of: initialOutput, with: "")
        return commandOutput
    }
}
