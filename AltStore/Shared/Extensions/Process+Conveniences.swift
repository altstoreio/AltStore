//
//  Process+Conveniences.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import OSLog
import Combine

@available(macOS 12, *)
extension Process
{
    // Based loosely off of https://developer.apple.com/forums/thread/690310
    class func launch(_ toolURL: URL, arguments: [String] = [], environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Process
    {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        
        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        func posixErr(_ error: Int32) -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil) }
        
        // If you write to a pipe whose remote end has closed, the OS raises a
        // `SIGPIPE` signal whose default disposition is to terminate your
        // process.  Helpful!  `F_SETNOSIGPIPE` disables that feature, causing
        // the write to fail with `EPIPE` instead.
        
        let fcntlResult = fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        guard fcntlResult >= 0 else { throw posixErr(errno) }
        
        // Actually run the process.
        try process.run()
        
        let outputTask = Task {
            do
            {
                let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: toolURL.lastPathComponent)
                
                // Automatically cancels when fileHandle closes.
                for try await line in outputPipe.fileHandleForReading.bytes.lines
                {
                    process.output += line + "\n"
                    process.outputPublisher.send(line)
                    
                    logger.notice("\(line, privacy: .public)")
                }
                
                try Task.checkCancellation()
                process.outputPublisher.send(completion: .finished)
            }
            catch let error as CancellationError
            {
                process.outputPublisher.send(completion: .failure(error))
            }
            catch
            {
                Logger.main.error("Failed to read process output. \(error.localizedDescription, privacy: .public)")
                
                try Task.checkCancellation()
                process.outputPublisher.send(completion: .failure(error))
            }
        }
        
        process.terminationHandler = { process in
            Logger.main.notice("Process \(toolURL, privacy: .public) terminated with exit code \(process.terminationStatus).")
            
            outputTask.cancel()
            process.outputPublisher.send(completion: .finished)
        }
        
        return process
    }
    
    class func launchAndWait(_ toolURL: URL, arguments: [String] = [], environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> String
    {
        let process = try self.launch(toolURL, arguments: arguments, environment: environment)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let previousHandler = process.terminationHandler
            process.terminationHandler = { process in
                previousHandler?(process)
                continuation.resume()
            }
        }
        
        guard process.terminationStatus == 0 else {
            throw ProcessError.failed(executableURL: toolURL, exitCode: process.terminationStatus, output: process.output)
        }
        
        return process.output
    }
}

@available(macOS 12, *)
extension Process
{
    private static var outputKey: Int = 0
    private static var publisherKey: Int = 0
    
    fileprivate(set) var output: String {
        get {
            let output = objc_getAssociatedObject(self, &Process.outputKey) as? String ?? ""
            return output
        }
        set {
            objc_setAssociatedObject(self, &Process.outputKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
    
    // Should be type-erased, but oh well.
    var outputLines: AsyncThrowingPublisher<some Publisher<String, Error>> {
        return self.outputPublisher
            .buffer(size: 100, prefetch: .byRequest, whenFull: .dropOldest)
            .values
    }
    
    private var outputPublisher: PassthroughSubject<String, Error> {
        if let publisher = objc_getAssociatedObject(self, &Process.publisherKey) as? PassthroughSubject<String, Error>
        {
            return publisher
        }
        
        let publisher = PassthroughSubject<String, Error>()
        objc_setAssociatedObject(self, &Process.publisherKey, publisher, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return publisher
    }
    
    // We must manually close outputPipe in order for us to read a second Process' standardOutput via async-await 🤷‍♂️
    func stopOutput()
    {
        guard let outputPipe = self.standardOutput as? Pipe else { return }
        
        do
        {
            try outputPipe.fileHandleForReading.close()
        }
        catch
        {
            Logger.main.error("Failed to close \(self.executableURL?.lastPathComponent ?? "process", privacy: .public)'s standardOutput. \(error.localizedDescription, privacy: .public)")
        }
    }
}
