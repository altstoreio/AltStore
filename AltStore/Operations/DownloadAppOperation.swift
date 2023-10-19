//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltStoreCore
import AltSign

@objc(DownloadAppOperation)
class DownloadAppOperation: ResultOperation<ALTApplication>
{
    let app: AppProtocol
    let context: InstallAppOperationContext
    
    private let appName: String
    private let bundleIdentifier: String
    private let destinationURL: URL
    
    private let session = URLSession(configuration: .default)
    private let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
    
    init(app: AppProtocol, destinationURL: URL, context: InstallAppOperationContext)
    {
        self.app = app
        self.context = context
        
        self.appName = app.name
        self.bundleIdentifier = app.bundleIdentifier
        self.destinationURL = destinationURL
        
        super.init()
        
        // App = 3, Dependencies = 1
        self.progress.totalUnitCount = 4
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        Logger.sideload.notice("Downloading app \(self.bundleIdentifier, privacy: .public)...")
        
        // Set _after_ checking self.context.error to prevent overwriting localized failure for previous errors.
        self.localizedFailure = String(format: NSLocalizedString("%@ could not be downloaded.", comment: ""), self.appName)
        
        guard let storeApp = self.app as? StoreApp else {
            // Only StoreApp allows falling back to previous versions.
            // AppVersion can only install itself, and ALTApplication doesn't have previous versions.
            return self.download(self.app)
        }
        
        // Verify storeApp
        storeApp.managedObjectContext?.perform {
            do
            {
                let latestVersion = try self.verify(storeApp)
                self.download(latestVersion)
            }
            catch let error as VerificationError where error.code == .iOSVersionNotSupported
            {
                guard let presentingViewController = self.context.presentingViewController, let latestSupportedVersion = storeApp.latestSupportedVersion
                else { return self.finish(.failure(error)) }
                
                if let installedApp = storeApp.installedApp
                {
                    guard !installedApp.matches(latestSupportedVersion) else { return self.finish(.failure(error)) }
                }
                
                let title = NSLocalizedString("Unsupported iOS Version", comment: "")
                let message = error.localizedDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
                let localizedVersion = latestSupportedVersion.localizedVersion
                                
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                        self.finish(.failure(OperationError.cancelled))
                    })
                    alertController.addAction(UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), self.appName, localizedVersion), style: .default) { _ in
                        self.download(latestSupportedVersion)
                    })
                    presentingViewController.present(alertController, animated: true)
                }
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
    
    override func finish(_ result: Result<ALTApplication, Error>)
    {
        do
        {
            try FileManager.default.removeItem(at: self.temporaryDirectory)
        }
        catch
        {
            Logger.sideload.error("Failed to remove DownloadAppOperation temporary directory: \(self.temporaryDirectory, privacy: .public). \(error.localizedDescription, privacy: .public)")
        }
        
        super.finish(result)
    }
}

private extension DownloadAppOperation
{
    func verify(_ storeApp: StoreApp) throws -> AppVersion
    {
        guard let version = storeApp.latestAvailableVersion else {
            let failureReason = String(format: NSLocalizedString("The latest version of %@ could not be determined.", comment: ""), self.appName)
            throw OperationError.unknown(failureReason: failureReason)
        }
        
        if let minOSVersion = version.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            throw VerificationError.iOSVersionNotSupported(app: storeApp, requiredOSVersion: minOSVersion)
        }
        else if let maxOSVersion = version.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            throw VerificationError.iOSVersionNotSupported(app: storeApp, requiredOSVersion: maxOSVersion)
        }
        
        return version
    }
    
    func download(@Managed _ app: AppProtocol)
    {
        guard let sourceURL = $app.url else { return self.finish(.failure(OperationError.appNotFound(name: self.appName))) }
        
        if let appVersion = app as? AppVersion
        {
            // All downloads go through this path, and `app` is
            // always an AppVersion if downloading from a source,
            // so context.appVersion != nil means downloading from source.
            self.context.appVersion = appVersion
        }
        
        self.downloadIPA(from: sourceURL) { result in
            do
            {
                let application = try result.get()
               
                if self.context.bundleIdentifier == StoreApp.dolphinAppID, self.context.bundleIdentifier != application.bundleIdentifier
                {
                    if var infoPlist = NSDictionary(contentsOf: application.bundle.infoPlistURL) as? [String: Any]
                    {
                        // Manually update the app's bundle identifier to match the one specified in the source.
                        // This allows people who previously installed the app to still update and refresh normally.
                        infoPlist[kCFBundleIdentifierKey as String] = StoreApp.dolphinAppID
                        (infoPlist as NSDictionary).write(to: application.bundle.infoPlistURL, atomically: true)
                    }
                }
                
                self.downloadDependencies(for: application) { result in
                    do
                    {
                        _ = try result.get()
                        
                        try FileManager.default.copyItem(at: application.fileURL, to: self.destinationURL, shouldReplace: true)
                                                
                        guard let copiedApplication = ALTApplication(fileURL: self.destinationURL) else { throw OperationError.invalidApp }
                        
                        Logger.sideload.notice("Downloaded app \(copiedApplication.bundleIdentifier, privacy: .public) from \(sourceURL, privacy: .public)")
                        
                        self.finish(.success(copiedApplication))
                        
                        self.progress.completedUnitCount += 1
                    }
                    catch
                    {
                        self.finish(.failure(error))
                    }
                }
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
    
    func downloadIPA(from sourceURL: URL, completionHandler: @escaping (Result<ALTApplication, Error>) -> Void)
    {
        func finishOperation(_ result: Result<URL, Error>)
        {
            do
            {
                let fileURL = try result.get()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { throw OperationError.appNotFound(name: self.appName) }
                
                try FileManager.default.createDirectory(at: self.temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                
                let appBundleURL: URL
                
                if isDirectory.boolValue
                {
                    // Directory, so assuming this is .app bundle.
                    guard Bundle(url: fileURL) != nil else { throw OperationError.invalidApp }
                    
                    appBundleURL = self.temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
                    try FileManager.default.copyItem(at: fileURL, to: appBundleURL)
                }
                else
                {
                    // File, so assuming this is a .ipa file.
                    appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: self.temporaryDirectory)
                    
                    // Use context's temporaryDirectory to ensure .ipa isn't deleted before we're done installing.
                    let ipaURL = self.context.temporaryDirectory.appendingPathComponent("App.ipa")
                    try FileManager.default.copyItem(at: fileURL, to: ipaURL)
                    
                    self.context.ipaURL = ipaURL
                }
                
                guard let application = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                completionHandler(.success(application))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        if sourceURL.isFileURL
        {
            finishOperation(.success(sourceURL))
            
            self.progress.completedUnitCount += 3
        }
        else
        {
            let downloadTask = self.session.downloadTask(with: sourceURL) { (fileURL, response, error) in
                do
                {
                    if let response = response as? HTTPURLResponse
                    {
                        guard response.statusCode != 404 else { throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: sourceURL]) }
                    }
                    
                    let (fileURL, _) = try Result((fileURL, response), error).get()
                    finishOperation(.success(fileURL))
                    
                    try? FileManager.default.removeItem(at: fileURL)
                }
                catch
                {
                    finishOperation(.failure(error))
                }
            }
            self.progress.addChild(downloadTask.progress, withPendingUnitCount: 3)
            
            downloadTask.resume()
        }
    }
}

private extension DownloadAppOperation
{
    struct AltStorePlist: Decodable
    {
        private enum CodingKeys: String, CodingKey
        {
            case dependencies = "ALTDependencies"
        }

        var dependencies: [Dependency]
    }

    struct Dependency: Decodable
    {
        var downloadURL: URL
        var path: String?
        
        var preferredFilename: String {
            let preferredFilename = self.path.map { ($0 as NSString).lastPathComponent } ?? self.downloadURL.lastPathComponent
            return preferredFilename
        }
        
        init(from decoder: Decoder) throws
        {
            enum CodingKeys: String, CodingKey
            {
                case downloadURL
                case path
            }
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            let urlString = try container.decode(String.self, forKey: .downloadURL)
            let path = try container.decodeIfPresent(String.self, forKey: .path)
            
            guard let downloadURL = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "downloadURL is not a valid URL.")
            }
            
            self.downloadURL = downloadURL
            self.path = path
        }
    }
    
    func downloadDependencies(for application: ALTApplication, completionHandler: @escaping (Result<Set<URL>, Error>) -> Void)
    {
        guard FileManager.default.fileExists(atPath: application.bundle.altstorePlistURL.path) else {
            return completionHandler(.success([]))
        }
        
        do
        {
            let data = try Data(contentsOf: application.bundle.altstorePlistURL)
            
            let altstorePlist = try PropertyListDecoder().decode(AltStorePlist.self, from: data)
                        
            var dependencyURLs = Set<URL>()
            var dependencyError: Error?
            
            let dispatchGroup = DispatchGroup()
            let progress = Progress(totalUnitCount: Int64(altstorePlist.dependencies.count), parent: self.progress, pendingUnitCount: 1)
            
            for dependency in altstorePlist.dependencies
            {
                dispatchGroup.enter()
                
                self.download(dependency, for: application, progress: progress) { result in
                    switch result
                    {
                    case .failure(let error): dependencyError = error
                    case .success(let fileURL): dependencyURLs.insert(fileURL)
                    }
                    
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(qos: .userInitiated, queue: .global()) {
                if let dependencyError = dependencyError
                {
                    completionHandler(.failure(dependencyError))
                }
                else
                {
                    completionHandler(.success(dependencyURLs))
                }
            }
        }
        catch let error as DecodingError
        {
            let nsError = (error as NSError).withLocalizedFailure(String(format: NSLocalizedString("The dependencies for %@ could not be determined.", comment: ""), application.name))
            completionHandler(.failure(nsError))
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func download(_ dependency: Dependency, for application: ALTApplication, progress: Progress, completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        let downloadTask = self.session.downloadTask(with: dependency.downloadURL) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                defer { try? FileManager.default.removeItem(at: fileURL) }
                
                let path = dependency.path ?? dependency.preferredFilename
                let destinationURL = application.fileURL.appendingPathComponent(path)
                
                let directoryURL = destinationURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directoryURL.path)
                {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }
                
                try FileManager.default.copyItem(at: fileURL, to: destinationURL, shouldReplace: true)
                
                completionHandler(.success(destinationURL))
            }
            catch let error as NSError
            {
                let localizedFailure = String(format: NSLocalizedString("The dependency “%@” could not be downloaded.", comment: ""), dependency.preferredFilename)
                completionHandler(.failure(error.withLocalizedFailure(localizedFailure)))
            }
        }
        progress.addChild(downloadTask.progress, withPendingUnitCount: 1)
        
        downloadTask.resume()
    }
}
