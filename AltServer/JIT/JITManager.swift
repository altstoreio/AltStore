//
//  JITManager.swift
//  AltServer
//
//  Created by Riley Testut on 8/30/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import RegexBuilder

import AltSign

private extension URL
{
    static let python3 = URL(fileURLWithPath: "/usr/bin/python3")
    static let altjit = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("altjit")
}

class JITManager
{
    static let shared = JITManager()
        
    private let diskManager = DeveloperDiskManager()
    
    private var authorization: AuthorizationRef?
    
    private init()
    {
    }
    
    func prepare(_ device: ALTDevice) async throws
    {
        let isMounted = try await ALTDeviceManager.shared.isDeveloperDiskImageMounted(for: device)
        guard !isMounted else { return }
        
        if #available(macOS 13, *), device.osVersion.majorVersion >= 17
        {
            // iOS 17+
            try await self.installPersonalizedDeveloperDisk(onto: device)
        }
        else
        {
            try await self.installDeveloperDisk(onto: device)
        }
    }
    
    func enableUnsignedCodeExecution(process: AppProcess, device: ALTDevice) async throws
    {
        try await self.prepare(device)
        
        if #available(macOS 13, *), device.osVersion.majorVersion >= 17
        {
            // iOS 17+
            try await self.enableModernUnsignedCodeExecution(process: process, device: device)
        }
        else
        {
            try await self.enableLegacyUnsignedCodeExecution(process: process, device: device)
        }
    }
}

private extension JITManager
{
    func installDeveloperDisk(onto device: ALTDevice) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.diskManager.downloadDeveloperDisk(for: device) { (result) in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success((let diskFileURL, let signatureFileURL)):
                    ALTDeviceManager.shared.installDeveloperDiskImage(at: diskFileURL, signatureURL: signatureFileURL, to: device) { (success, error) in
                        switch Result(success, error)
                        {
                        case .failure(let error as ALTServerError) where error.code == .incompatibleDeveloperDisk:
                            self.diskManager.setDeveloperDiskCompatible(false, with: device)
                            continuation.resume(throwing: error)
                            
                        case .failure(let error):
                            // Don't mark developer disk as incompatible because it probably failed for a different reason.
                            continuation.resume(throwing: error)
                            
                        case .success:
                            self.diskManager.setDeveloperDiskCompatible(true, with: device)
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
    
    func enableLegacyUnsignedCodeExecution(process: AppProcess, device: ALTDevice) async throws
    {
        let connection = try await ALTDeviceManager.shared.startDebugConnection(to: device)
        
        switch process
        {
        case .name(let name): try await connection.enableUnsignedCodeExecutionForProcess(withName: name)
        case .pid(let pid): try await connection.enableUnsignedCodeExecutionForProcess(withID: pid)
        }
    }
}

@available(macOS 13, *)
private extension JITManager
{
    func installPersonalizedDeveloperDisk(onto device: ALTDevice) async throws
    {
        do
        {
            _ = try await Process.launchAndWait(.altjit, arguments: ["mount", "--udid", device.identifier])
        }
        catch
        {
            try self.processAltJITError(error)
        }
    }
    
    func enableModernUnsignedCodeExecution(process: AppProcess, device: ALTDevice) async throws
    {
        do
        {
            if self.authorization == nil
            {
                // runAsAdmin() only returns authorization if the process completes successfully,
                // so we request authorization for a command that can't fail, then re-use it for the failable command below.
                self.authorization = try Process.runAsAdmin("echo", arguments: ["altstore"], authorization: self.authorization)
            }
            
            var arguments = ["enable"]
            switch process
            {
            case .name(let name): arguments.append(name)
            case .pid(let pid): arguments.append(String(pid))
            }
            arguments += ["--udid", device.identifier]
            
            self.authorization = try Process.runAsAdmin(URL.altjit.path, arguments: arguments, authorization: self.authorization)
        }
        catch
        {
            try self.processAltJITError(error)
        }
    }
    
    func processAltJITError(_ error: some Error) throws
    {
        do
        {
            throw error
        }
        catch let error as ProcessError where error.code == .failed
        {
            guard let output = error.output else { throw error }
            
            let dependencyNotFoundRegex = Regex {
                "No module named"
                
                OneOrMore(.whitespace)
                
                Capture {
                    OneOrMore(.anyNonNewline)
                }
            }
            
            let deviceNotFoundRegex = Regex {
                "Device is not connected"
            }
            
            if let match = output.firstMatch(of: dependencyNotFoundRegex)
            {
                let dependency = String(match.1)
                throw JITError.dependencyNotFound(dependency)
            }
            else if output.contains(deviceNotFoundRegex)
            {
                throw ALTServerError(.deviceNotFound, userInfo: [
                    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Your device must be plugged into your computer to enable JIT on iOS 17 or later.", comment: "")
                ])
            }
            
            throw error
        }
    }
}
