//
//  PatchAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 10/13/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine
import AppleArchive
import System

import AltStoreCore
import AltSign
import Roxas

protocol PatchAppContext
{
    var bundleIdentifier: String { get }
    var temporaryDirectory: URL { get }
    
    var resignedApp: ALTApplication? { get }
    var error: Error? { get }
}

extension PatchAppError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = PatchAppError
        
        case unsupportedOperatingSystemVersion
    }
    
    static func unsupportedOperatingSystemVersion(_ osVersion: OperatingSystemVersion) -> PatchAppError { PatchAppError(code: .unsupportedOperatingSystemVersion, osVersion: osVersion) }
}

struct PatchAppError: ALTLocalizedError
{
    let code: Code
    var errorFailure: String?
    var errorTitle: String?
    
    var osVersion: OperatingSystemVersion?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unsupportedOperatingSystemVersion:
            let osVersionString: String
            if let osVersion = self.osVersion?.stringValue
            {
                osVersionString = NSLocalizedString("iOS", comment: "") + " " + osVersion
            }
            else
            {
                osVersionString = NSLocalizedString("your device's iOS version", comment: "")
            }
            
            let errorDescription = String(format: NSLocalizedString("The OTA download URL for %@ could not be determined.", comment: ""), osVersionString)
            return errorDescription
        }
    }
}

private struct OTAUpdate
{
    var url: URL
    var archivePath: String
}

class PatchAppOperation: ResultOperation<Void>, @unchecked Sendable
{
    let context: PatchAppContext
    
    var progressHandler: ((Progress, String) -> Void)?
    
    private let appPatcher = ALTAppPatcher()
    private lazy var patchDirectory: URL = self.context.temporaryDirectory.appendingPathComponent("Patch", isDirectory: true)
    
    private var cancellable: AnyCancellable?
    
    init(context: PatchAppContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let resignedApp = self.context.resignedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        self.progressHandler?(self.progress, NSLocalizedString("Downloading iOS firmware...", comment: ""))
                
        self.cancellable = self.fetchOTAUpdate()
            .flatMap { self.downloadArchive(from: $0) }
            .flatMap { self.extractSpotlightFromArchive(at: $0) }
            .flatMap { self.patch(resignedApp, withBinaryAt: $0) }
            .tryMap { try FileManager.default.zipAppBundle(at: $0) }
            .tryMap { (fileURL) in
                let app = AnyApp(name: resignedApp.name, bundleIdentifier: self.context.bundleIdentifier, url: resignedApp.fileURL, storeApp: nil)
                
                let destinationURL = InstalledApp.refreshedIPAURL(for: app)
                try FileManager.default.copyItem(at: fileURL, to: destinationURL, shouldReplace: true)
            }
            .receive(on: RunLoop.main)
            .sink { completion in
                switch completion
                {
                case .failure(let error): self.finish(.failure(error))
                case .finished: self.finish(.success(()))
                }
            } receiveValue: { _ in }
    }
    
    override func cancel()
    {
        super.cancel()
        
        self.cancellable?.cancel()
        self.cancellable = nil
    }
}

private let ALTFragmentZipCallback: @convention(c) (UInt32) -> Void = { (percentageComplete) in
    guard let progress = Progress.current() else { return }
    
    if percentageComplete == 100 && progress.completedUnitCount == 0
    {
        // Ignore first percentageComplete, which is always 100.
        return
    }
    
    progress.completedUnitCount = Int64(percentageComplete)
}

private extension PatchAppOperation
{
    func fetchOTAUpdate() -> AnyPublisher<OTAUpdate, Error>
    {
        Just(()).tryMap {
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            switch (osVersion.majorVersion, osVersion.minorVersion)
            {
            case (14, 3):
                return OTAUpdate(url: URL(string: "https://updates.cdn-apple.com/2020WinterFCS/patches/001-87330/99E29969-F6B6-422A-B946-70DE2E2D73BE/com_apple_MobileAsset_SoftwareUpdate/67f9e42f5e57a20e0a87eaf81b69dd2a61311d3f.zip")!,
                                   archivePath: "AssetData/payloadv2/payload.042")
                
            case (14, 4):
                return OTAUpdate(url: URL(string: "https://updates.cdn-apple.com/2021WinterFCS/patches/001-98606/43AF99A1-F286-43B1-A101-F9F856EA395A/com_apple_MobileAsset_SoftwareUpdate/c4985c32c344beb7b49c61919b4e39d1fd336c90.zip")!,
                                   archivePath: "AssetData/payloadv2/payload.042")
                
            case (14, 5):
                return OTAUpdate(url: URL(string: "https://updates.cdn-apple.com/2021SpringFCS/patches/061-84483/AB525139-066E-46F8-8E85-DCE802C03BA8/com_apple_MobileAsset_SoftwareUpdate/788573ae93113881db04269acedeecabbaa643e3.zip")!,
                                   archivePath: "AssetData/payloadv2/payload.043")
                
            default: throw PatchAppError.unsupportedOperatingSystemVersion(osVersion)
            }
        }
        .eraseToAnyPublisher()
    }
    
    func downloadArchive(from update: OTAUpdate) -> AnyPublisher<URL, Error>
    {
        Just(()).tryMap {
            #if targetEnvironment(simulator) || MARKETPLACE
            throw PatchAppError.unsupportedOperatingSystemVersion(ProcessInfo.processInfo.operatingSystemVersion)
            #else
            
            try FileManager.default.createDirectory(at: self.patchDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let archiveURL = self.patchDirectory.appendingPathComponent("ota.archive")
            try archiveURL.withUnsafeFileSystemRepresentation { archivePath in
                guard let fz = fragmentzip_open((update.url.absoluteString as NSString).utf8String!) else {
                    throw URLError(.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("The connection failed because a connection cannot be made to the host.", comment: ""),
                                                                                NSURLErrorKey: update.url])
                }
                defer { fragmentzip_close(fz) }
                
                self.progress.becomeCurrent(withPendingUnitCount: 100)
                defer { self.progress.resignCurrent() }
                
                guard fragmentzip_download_file(fz, update.archivePath, archivePath!, ALTFragmentZipCallback) == 0 else {
                    throw URLError(.networkConnectionLost, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("The connection failed because the network connection was lost.", comment: ""),
                                                                                NSURLErrorKey: update.url])
                }
            }
            
            Logger.fugu14.notice("Downloaded iOS OTA archive.")
            return archiveURL
            
            #endif
        }
        .mapError { ($0 as NSError).withLocalizedFailure(NSLocalizedString("Could not download OTA archive.", comment: "")) }
        .eraseToAnyPublisher()
    }
    
    func extractSpotlightFromArchive(at archiveURL: URL) -> AnyPublisher<URL, Error>
    {
        Just(()).tryMap {
            #if targetEnvironment(simulator)
            throw PatchAppError.unsupportedOperatingSystemVersion(ProcessInfo.processInfo.operatingSystemVersion)
            #else
            
            let spotlightPath = "Applications/Spotlight.app/Spotlight"
            let spotlightFileURL = self.patchDirectory.appendingPathComponent(spotlightPath)
            
            guard let readFileStream = ArchiveByteStream.fileStream(path: FilePath(archiveURL.path), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o644)),
                  let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readFileStream),
                  let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream),
                  let readStream = ArchiveStream.extractStream(extractingTo: FilePath(self.patchDirectory.path))
            else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: archiveURL]) }
            
            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: readStream) { message, filePath, data in
                guard filePath == FilePath(spotlightPath) else { return .skip }
                return .ok
            }
            
            Logger.fugu14.notice("Extracted Spotlight from OTA archive.")
            return spotlightFileURL
            
            #endif
        }
        .mapError { ($0 as NSError).withLocalizedFailure(NSLocalizedString("Could not extract Spotlight from OTA archive.", comment: "")) }
        .eraseToAnyPublisher()
    }
    
    func patch(_ app: ALTApplication, withBinaryAt patchFileURL: URL) -> AnyPublisher<URL, Error>
    {
        Just(()).tryMap {
            // executableURL may be nil, so use infoDictionary instead to determine executable name.
            // guard let appName = app.bundle.executableURL?.lastPathComponent else { throw OperationError.invalidApp }
            guard let appName = app.bundle.infoDictionary?[kCFBundleExecutableKey as String] as? String else { throw OperationError.invalidApp }
                        
            let temporaryAppURL = self.patchDirectory.appendingPathComponent("Patched.app", isDirectory: true)
            try FileManager.default.copyItem(at: app.fileURL, to: temporaryAppURL)
            
            let appBinaryURL = temporaryAppURL.appendingPathComponent(appName, isDirectory: false)
            try self.appPatcher.patchAppBinary(at: appBinaryURL, withBinaryAt: patchFileURL)
            
            Logger.fugu14.notice("Patched \(app.name, privacy: .public)!")
            return temporaryAppURL
        }
        .mapError { ($0 as NSError).withLocalizedFailure(String(format: NSLocalizedString("Could not patch %@ placeholder.", comment: ""), app.name)) }
        .eraseToAnyPublisher()
    }
}
