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

private extension DownloadAppOperation
{
    struct DependencyError: ALTLocalizedError
    {
        let dependency: Dependency
        let error: Error
        
        var failure: String? {
            return String(format: NSLocalizedString("Could not download “%@”.", comment: ""), self.dependency.preferredFilename)
        }
        
        var underlyingError: Error? {
            return self.error
        }
    }
}

@objc(DownloadAppOperation)
class DownloadAppOperation: ResultOperation<ALTApplication>
{
    let app: AppProtocol
    let context: AppOperationContext
    
    private let bundleIdentifier: String
    private let sourceURL: URL
    private let destinationURL: URL
    
    private let session = URLSession(configuration: .default)
    private let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
    
    init(app: AppProtocol, destinationURL: URL, context: AppOperationContext)
    {
        self.app = app
        self.context = context
        
        self.bundleIdentifier = app.bundleIdentifier
        self.sourceURL = app.url
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
        
        print("Downloading App:", self.bundleIdentifier)
        
        self.downloadApp(from: self.sourceURL) { result in
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
    
    override func finish(_ result: Result<ALTApplication, Error>)
    {
        do
        {
            try FileManager.default.removeItem(at: self.temporaryDirectory)
        }
        catch
        {
            print("Failed to remove DownloadAppOperation temporary directory: \(self.temporaryDirectory).", error)
        }
        
        super.finish(result)
    }
}

private extension DownloadAppOperation
{
    func downloadApp(from sourceURL: URL, completionHandler: @escaping (Result<ALTApplication, Error>) -> Void)
    {
        func finishOperation(_ result: Result<URL, Error>)
        {
            do
            {
                let fileURL = try result.get()
                
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { throw OperationError.appNotFound }
                
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
                }
                
                guard let application = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                completionHandler(.success(application))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        if self.sourceURL.isFileURL
        {
            finishOperation(.success(sourceURL))
            
            self.progress.completedUnitCount += 3
        }
        else
        {
            let downloadTask = self.session.downloadTask(with: sourceURL) { (fileURL, response, error) in
                do
                {
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
            var dependencyError: DependencyError?
            
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
            let nsError = (error as NSError).withLocalizedFailure(String(format: NSLocalizedString("Could not download dependencies for %@.", comment: ""), application.name))
            completionHandler(.failure(nsError))
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func download(_ dependency: Dependency, for application: ALTApplication, progress: Progress, completionHandler: @escaping (Result<URL, DependencyError>) -> Void)
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
            catch
            {
                completionHandler(.failure(DependencyError(dependency: dependency, error: error)))
            }
        }
        progress.addChild(downloadTask.progress, withPendingUnitCount: 1)
        
        downloadTask.resume()
    }
}
