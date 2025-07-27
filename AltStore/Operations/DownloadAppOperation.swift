//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import WebKit
import UniformTypeIdentifiers

import AltStoreCore
import AltSign
import Roxas

@objc(DownloadAppOperation)
class DownloadAppOperation: ResultOperation<ALTApplication>, @unchecked Sendable
{
    @Managed
    private(set) var app: AppProtocol
    
    let context: InstallAppOperationContext
    
    private let appName: String
    private let bundleIdentifier: String
    private let destinationURL: URL
    
    private let session = URLSession(configuration: .sharedCookies)
    private let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
    
    private var downloadPatreonAppContinuation: CheckedContinuation<URL, Error>?
    
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
        
        self.$app.perform { app in
            do
            {
                var appVersion: AppVersion?
                
                if let version = app as? AppVersion
                {
                    appVersion = version
                }
                else if let storeApp = app as? StoreApp
                {
                    guard let latestVersion = storeApp.latestAvailableVersion else {
                        let failureReason = String(format: NSLocalizedString("The latest version of %@ could not be determined.", comment: ""), self.appName)
                        throw OperationError.unknown(failureReason: failureReason)
                    }
                    
                    // Attempt to download latest _available_ version, and fall back to older versions if necessary.
                    appVersion = latestVersion
                }
                
                if let appVersion
                {
                    try self.verify(appVersion)
                }
                
                self.download(appVersion ?? app)
            }
            catch let error as VerificationError where error.code == .iOSVersionNotSupported
            {
                guard let presentingViewController = self.context.presentingViewController, let storeApp = app.storeApp, let latestSupportedVersion = storeApp.latestSupportedVersion
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
    func verify(_ version: AppVersion) throws
    {
        if let minOSVersion = version.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: minOSVersion)
        }
        else if let maxOSVersion = version.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: maxOSVersion)
        }
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
        Task<Void, Never>.detached(priority: .userInitiated) {
            do
            {
                let fileURL: URL
                
                if sourceURL.isFileURL
                {
                    fileURL = sourceURL
                    self.progress.completedUnitCount += 3
                }
                else if let host = sourceURL.host, host.lowercased().hasSuffix("patreon.com") && sourceURL.path.lowercased() == "/file"
                {
                    // Patreon app
                    fileURL = try await self.downloadPatreonApp(from: sourceURL)
                }
                else
                {
                    // Regular app
                    fileURL = try await self.downloadFile(from: sourceURL)
                }
                
                defer {
                    if !sourceURL.isFileURL
                    {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
                
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
    }
    
    func downloadFile(from downloadURL: URL) async throws -> URL
    {
        try await withCheckedThrowingContinuation { continuation in
            let downloadTask = self.session.downloadTask(with: downloadURL) { (fileURL, response, error) in
                do
                {
                    if let response = response as? HTTPURLResponse
                    {
                        guard response.statusCode != 403 else { throw URLError(.noPermissionsToReadFile) }
                        guard response.statusCode != 404 else { throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: downloadURL]) }
                    }
                    
                    let (fileURL, _) = try Result((fileURL, response), error).get()
                    continuation.resume(returning: fileURL)
                }
                catch
                {
                    continuation.resume(throwing: error)
                }
            }
            self.progress.addChild(downloadTask.progress, withPendingUnitCount: 3)
            
            downloadTask.resume()
        }
    }
    
    func downloadPatreonApp(from patreonURL: URL) async throws -> URL
    {
        guard !UserDefaults.shared.skipPatreonDownloads else {
            // Skip all hacks, take user straight to Patreon post.
            return try await downloadFromPatreonPost()
        }
        
        do
        {
            // User is pledged to this app, attempt to download.
            
            let fileURL = try await self.downloadFile(from: patreonURL)
            return fileURL
        }
        catch URLError.noPermissionsToReadFile
        {
            guard let presentingViewController = self.context.presentingViewController else { throw OperationError.pledgeRequired(appName: self.appName) }
            
            // Attempt to sign-in again in case our Patreon session has expired.
            try await withCheckedThrowingContinuation { continuation in
                PatreonAPI.shared.authenticate(presentingViewController: presentingViewController) { result in
                    do
                    {
                        let account = try result.get()
                        try account.managedObjectContext?.save()
                        
                        continuation.resume()
                    }
                    catch
                    {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            do
            {
                // Success, so try to download once more now that we're definitely authenticated.
                
                let fileURL = try await self.downloadFile(from: patreonURL)
                return fileURL
            }
            catch URLError.noPermissionsToReadFile
            {
                // We know authentication succeeded, so failure must mean user isn't patron/on the correct tier,
                // or that our hacky workaround for downloading Patreon attachments has failed.
                // Either way, taking them directly to the post serves as a decent fallback.
                
                return try await downloadFromPatreonPost()
            }
        }
        
        func downloadFromPatreonPost() async throws -> URL
        {
            guard let presentingViewController = self.context.presentingViewController else { throw OperationError.pledgeRequired(appName: self.appName) }
            
            let downloadURL: URL
            
            if let components = URLComponents(url: patreonURL, resolvingAgainstBaseURL: false),
                  let postItem = components.queryItems?.first(where: { $0.name == "h" }),
                  let postID = postItem.value,
                  let patreonPostURL = URL(string: "https://www.patreon.com/posts/" + postID)
            {
                downloadURL = patreonPostURL
            }
            else
            {
                downloadURL = patreonURL
            }
            
            return try await self.downloadFromPatreon(downloadURL, presentingViewController: presentingViewController)
        }
    }
    
    @MainActor
    func downloadFromPatreon(_ patreonURL: URL, presentingViewController: UIViewController) async throws -> URL
    {
        let webViewController = WebViewController(url: patreonURL)
        webViewController.delegate = self
        webViewController.webView.navigationDelegate = self
        
        let navigationController = UINavigationController(rootViewController: webViewController)
        presentingViewController.present(navigationController, animated: true)
        
        let downloadURL: URL
        
        do
        {
            defer {
                navigationController.dismiss(animated: true)
            }
            
            downloadURL = try await withCheckedThrowingContinuation { continuation in
                self.downloadPatreonAppContinuation = continuation
            }
        }
        
        let fileURL = try await self.downloadFile(from: downloadURL)
        return fileURL
    }
}

extension DownloadAppOperation: WebViewControllerDelegate
{
    func webViewControllerDidFinish(_ webViewController: WebViewController) 
    {
        guard let continuation = self.downloadPatreonAppContinuation else { return }
        self.downloadPatreonAppContinuation = nil
        
        continuation.resume(throwing: CancellationError())
    }
}

extension DownloadAppOperation: WKNavigationDelegate
{
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy 
    {
        guard #available(iOS 14.5, *), navigationAction.shouldPerformDownload else { return .allow }
        
        guard let continuation = self.downloadPatreonAppContinuation else { return .allow }
        self.downloadPatreonAppContinuation = nil
        
        if let downloadURL = navigationAction.request.url
        {
            continuation.resume(returning: downloadURL)
        }
        else
        {
            continuation.resume(throwing: URLError(.badURL))
        }
        
        return .cancel
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy 
    {
        // Called for Patreon attachments
        
        guard !navigationResponse.canShowMIMEType else { return .allow }
        
        guard let continuation = self.downloadPatreonAppContinuation else { return .allow }
        self.downloadPatreonAppContinuation = nil
        
        guard let response = navigationResponse.response as? HTTPURLResponse, let responseURL = response.url,
              let mimeType = response.mimeType, let type = UTType(mimeType: mimeType),
              type.conforms(to: .ipa) || type.conforms(to: .zip) || type.conforms(to: .application)
        else {
            continuation.resume(throwing: OperationError.invalidApp)
            return .cancel
        }
        
        continuation.resume(returning: responseURL)
        
        return .cancel
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
