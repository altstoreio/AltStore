//
//  PluginManager.swift
//  AltServer
//
//  Created by Riley Testut on 9/16/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AppKit
import CryptoKit

import STPrivilegedTask

private let pluginDirectoryURL = URL(fileURLWithPath: "/Library/Mail/Bundles", isDirectory: true)
private let pluginURL = pluginDirectoryURL.appendingPathComponent("AltPlugin.mailbundle")

enum PluginError: LocalizedError
{
    case cancelled
    case unknown
    case notFound
    case mismatchedHash(hash: String, expectedHash: String)
    case taskError(String)
    case taskErrorCode(Int)
    
    var errorDescription: String? {
        switch self
        {
        case .cancelled: return NSLocalizedString("Mail plug-in installation was cancelled.", comment: "")
        case .unknown: return NSLocalizedString("Failed to install Mail plug-in.", comment: "")
        case .notFound: return NSLocalizedString("The Mail plug-in does not exist at the requested URL.", comment: "")
        case .mismatchedHash(let hash, let expectedHash): return String(format: NSLocalizedString("The hash of the downloaded Mail plug-in does not match the expected hash.\n\nHash:\n%@\n\nExpected Hash:\n%@", comment: ""), hash, expectedHash)
        case .taskError(let output): return output
        case .taskErrorCode(let errorCode): return String(format: NSLocalizedString("There was an error installing the Mail plug-in. (Error Code: %@)", comment: ""), NSNumber(value: errorCode))
        }
    }
}

private extension URL
{
    #if STAGING
    static let altPluginUpdateURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altserver/altplugin/altplugin2.json")!
    #else
    static let altPluginUpdateURL = URL(string: "https://cdn.altstore.io/file/altstore/altserver/altplugin/altplugin.json")!
    #endif
}

class PluginManager
{
    private let session = URLSession(configuration: .ephemeral)
    private var latestPluginVersion: PluginVersion?
    
    var isMailPluginInstalled: Bool {
        let isMailPluginInstalled = FileManager.default.fileExists(atPath: pluginURL.path)
        return isMailPluginInstalled
    }

    func isUpdateAvailable(completionHandler: @escaping (Result<Bool, Error>) -> Void)
    {
        self.isUpdateAvailable(useCache: false, completionHandler: completionHandler)
    }
    
    private func isUpdateAvailable(useCache: Bool, completionHandler: @escaping (Result<Bool, Error>) -> Void)
    {
        do
        {
            // If Mail plug-in is not yet installed, then there is no update available.
            guard let bundle = Bundle(url: pluginURL) else { return completionHandler(.success(false)) }
            
            // Load Info.plist from disk because Bundle.infoDictionary is cached by system.
            let infoDictionaryURL = bundle.bundleURL.appendingPathComponent("Contents/Info.plist")
            guard let infoDictionary = NSDictionary(contentsOf: infoDictionaryURL) as? [String: Any],
                  let localVersion = infoDictionary["CFBundleShortVersionString"] as? String
            else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: infoDictionaryURL]) }
                        
            if let pluginVersion = self.latestPluginVersion, useCache
            {
                let isUpdateAvailable = (localVersion != pluginVersion.version)
                completionHandler(.success(isUpdateAvailable))
            }
            else
            {
                self.fetchLatestPluginVersion(useCache: useCache) { result in
                    switch result
                    {
                    case .failure(let error): completionHandler(.failure(error))
                    case .success(let pluginVersion):
                        let isUpdateAvailable = (localVersion != pluginVersion.version)
                        completionHandler(.success(isUpdateAvailable))
                    }
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
}

extension PluginManager
{
    func installMailPlugin(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.isUpdateAvailable(useCache: true) { result in
            DispatchQueue.main.async {
                do
                {
                    let isUpdateAvailable = try result.get()
                    
                    let alert = NSAlert()
                    if isUpdateAvailable
                    {
                        alert.messageText = NSLocalizedString("Update Mail Plug-in", comment: "")
                        alert.informativeText = NSLocalizedString("An update is available for AltServer's Mail plug-in. Please update the plug-in now in order to keep using AltStore.", comment: "")
                        
                        alert.addButton(withTitle: NSLocalizedString("Update Plug-in", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                    }
                    else
                    {
                        alert.messageText = NSLocalizedString("Install Mail Plug-in", comment: "")
                        alert.informativeText = NSLocalizedString("AltServer requires a Mail plug-in in order to retrieve necessary information about your Apple ID. Would you like to install it now?", comment: "")
                        
                        alert.addButton(withTitle: NSLocalizedString("Install Plug-in", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                    }
                    
                    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                    
                    let response = alert.runModal()
                    guard response == .alertFirstButtonReturn else { throw PluginError.cancelled }
                    
                    self.downloadPlugin { (result) in
                        do
                        {
                            let fileURL = try result.get()
                            
                            // Ensure plug-in directory exists.
                            let authorization = try self.runAndKeepAuthorization("mkdir", arguments: ["-p", pluginDirectoryURL.path])
                            
                            // Create temporary directory.
                            let temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                            defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
                                
                            // Unzip AltPlugin to temporary directory.
                            try self.runAndKeepAuthorization("unzip", arguments: ["-o", fileURL.path, "-d", temporaryDirectoryURL.path], authorization: authorization)
                            
                            if FileManager.default.fileExists(atPath: pluginURL.path)
                            {
                                // Delete existing Mail plug-in.
                                try self.runAndKeepAuthorization("rm", arguments: ["-rf", pluginURL.path], authorization: authorization)
                            }
                            
                            // Copy AltPlugin to Mail plug-ins directory.
                            // Must be separate step than unzip to prevent macOS from considering plug-in corrupted.
                            let unzippedPluginURL = temporaryDirectoryURL.appendingPathComponent(pluginURL.lastPathComponent)
                            try self.runAndKeepAuthorization("cp", arguments: ["-R", unzippedPluginURL.path, pluginDirectoryURL.path], authorization: authorization)
                            
                            guard self.isMailPluginInstalled else { throw PluginError.unknown }
                            
                            // Enable Mail plug-in preferences.
                            try self.run("defaults", arguments: ["write", "/Library/Preferences/com.apple.mail", "EnableBundles", "-bool", "YES"], authorization: authorization)
                            
                            print("Finished installing Mail plug-in!")
                            
                            completionHandler(.success(()))
                        }
                        catch
                        {
                            completionHandler(.failure(error))
                        }
                    }
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
    }
    
    func uninstallMailPlugin(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Uninstall Mail Plug-in", comment: "")
        alert.informativeText = NSLocalizedString("Are you sure you want to uninstall the AltServer Mail plug-in? You will no longer be able to install or refresh apps with AltStore.", comment: "")
        
        alert.addButton(withTitle: NSLocalizedString("Uninstall Plug-in", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return completionHandler(.failure(PluginError.cancelled)) }
        
        DispatchQueue.global().async {
            do
            {
                if FileManager.default.fileExists(atPath: pluginURL.path)
                {
                    // Delete Mail plug-in from privileged directory.
                    try self.run("rm", arguments: ["-rf", pluginURL.path])
                }
                
                completionHandler(.success(()))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
}

private extension PluginManager
{
    func fetchLatestPluginVersion(useCache: Bool, completionHandler: @escaping (Result<PluginVersion, Error>) -> Void)
    {
        if let pluginVersion = self.latestPluginVersion, useCache
        {
            return completionHandler(.success(pluginVersion))
        }
        
        guard #available(macOS 11, *) else {
            // macOS versions prior to 11.0 require Mail plug-ins be *unsigned*,
            // so we hardcode these versions to use the unsigned AltPlugin v1.0.
            return completionHandler(.success(.v1_0))
        }
        
        let dataTask = self.session.dataTask(with: .altPluginUpdateURL) { (data, response, error) in
            do
            {
                if let response = response as? HTTPURLResponse
                {
                    guard response.statusCode != 404 else { return completionHandler(.failure(PluginError.notFound)) }
                }
                
                guard let data = data else { throw error! }
                
                let response = try JSONDecoder().decode(PluginVersionResponse.self, from: data)
                completionHandler(.success(response.pluginVersion))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        dataTask.resume()
    }
    
    func downloadPlugin(completion: @escaping (Result<URL, Error>) -> Void)
    {
        self.fetchLatestPluginVersion(useCache: true) { result in
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success(let pluginVersion):
                
                func finish(_ result: Result<URL, Error>)
                {
                    do
                    {
                        let fileURL = try result.get()
                        
                        if #available(OSX 10.15, *)
                        {
                            let data = try Data(contentsOf: fileURL)
                            let sha256Hash = SHA256.hash(data: data)
                            let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()
                            
                            print("Comparing Mail plug-in hash (\(hashString)) against expected hash (\(pluginVersion.sha256Hash))...")
                            guard hashString == pluginVersion.sha256Hash else { throw PluginError.mismatchedHash(hash: hashString, expectedHash: pluginVersion.sha256Hash) }
                        }
                        
                        completion(.success(fileURL))
                    }
                    catch
                    {
                        completion(.failure(error))
                    }
                }
                
                if pluginVersion.url.isFileURL
                {
                    finish(.success(pluginVersion.url))
                }
                else
                {
                    let downloadTask = URLSession.shared.downloadTask(with: pluginVersion.url) { (fileURL, response, error) in
                        if let response = response as? HTTPURLResponse
                        {
                            guard response.statusCode != 404 else { return finish(.failure(PluginError.notFound)) }
                        }
                        
                        let result = Result(fileURL, error)
                        finish(result)
                        
                        if let fileURL = fileURL
                        {
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                    
                    downloadTask.resume()
                }
            }
        }
    }
    
    func run(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil) throws
    {
        _ = try self._run(program, arguments: arguments, authorization: authorization, freeAuthorization: true)
    }
    
    @discardableResult
    func runAndKeepAuthorization(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil) throws -> AuthorizationRef
    {
        return try self._run(program, arguments: arguments, authorization: authorization, freeAuthorization: false)
    }
    
    func _run(_ program: String, arguments: [String], authorization: AuthorizationRef? = nil, freeAuthorization: Bool) throws -> AuthorizationRef
    {
        var launchPath = "/usr/bin/" + program
        if !FileManager.default.fileExists(atPath: launchPath)
        {
            launchPath = "/bin/" + program
        }
        
        print("Running program:", launchPath)
        
        let task = STPrivilegedTask()
        task.launchPath = launchPath
        task.arguments = arguments
        task.freeAuthorizationWhenDone = freeAuthorization
        
        let errorCode: OSStatus
        
        if let authorization = authorization
        {
            errorCode = task.launch(withAuthorization: authorization)
        }
        else
        {
            errorCode = task.launch()
        }
        
        guard errorCode == 0 else { throw PluginError.taskErrorCode(Int(errorCode)) }
        
        task.waitUntilExit()
        
        print("Exit code:", task.terminationStatus)
        
        guard task.terminationStatus == 0 else {
            let outputData = task.outputFileHandle.readDataToEndOfFile()
            
            if let outputString = String(data: outputData, encoding: .utf8), !outputString.isEmpty
            {
                throw PluginError.taskError(outputString)
            }
            
            throw PluginError.taskErrorCode(Int(task.terminationStatus))
        }
        
        guard let authorization = task.authorization else { throw PluginError.unknown }
        return authorization
    }
}
