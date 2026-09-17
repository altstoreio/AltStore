//
//  LocalAnisetteDataManager.swift
//  AltServer
//
//  Created by Caroline Moore on 9/15/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit
import OSLog

import AltSign
import AnisetteKit

private extension URL
{
    static let anisetteLibraries = URL(string: "https://apps.mzstatic.com/content/android-apple-music-apk/applemusic.apk")!

    static let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
}

// Swift wrapper around AnisetteKit to generate anisette data when macOS won't provide it.
class LocalAnisetteDataManager
{
    static let shared = LocalAnisetteDataManager()
    
    private init() {}
    
    func fetchAnisetteData() async throws -> ALTAnisetteData
    {
        let anisetteID: String
        if let cachedAnisetteID = UserDefaults.standard.anisetteID
        {
            anisetteID = cachedAnisetteID
        }
        else
        {
            anisetteID = UUID().uuidString
            UserDefaults.standard.anisetteID = anisetteID
        }
        
        guard let identifier = UUID(uuidString: anisetteID) else { throw AnisetteError.missingValue("anisetteID") }
        
        do
        {
            try await self.prepareLibraries()
            return try await self.makeAnisetteData(for: identifier)
        }
        catch AnisetteKit.AnisetteError.adiError(let code, let description)
        {
            // Rejected provisioning never becomes valid again, so delete it and re-provision.
            Logger.main.error("The anisette provisioning was rejected (Code: \(code). \(description, privacy: .public)). Provisioning again from scratch.")
            
            do
            {
                // AnisetteKit saves provisioning in a directory named after the lowercased identifier.
                let provisioningDirectory = FileManager.default.anisetteDirectory.appendingPathComponent(identifier.uuidString.lowercased())
                try FileManager.default.removeItem(at: provisioningDirectory)
            }
            catch
            {
                Logger.main.error("Failed to remove ADI directory. \(error.localizedDescription, privacy: .public)")
                throw AnisetteKit.AnisetteError.adiError(code: code, description: description)
            }
            
            do
            {
                return try await self.makeAnisetteData(for: identifier)
            }
            catch
            {
                throw AnisetteError.localAnisetteFailed(underlyingError: error)
            }
        }
        catch
        {
            throw AnisetteError.localAnisetteFailed(underlyingError: error)
        }
    }
}

private extension LocalAnisetteDataManager
{
    func prepareLibraries() async throws
    {
        let librariesDirectory = FileManager.default.anisetteLibrariesDirectory
        
        let librariesExist = AnisetteClient.validateLibrariesExist(at: librariesDirectory)
        guard !librariesExist else { return }
        
        Logger.main.notice("Downloading anisette libraries from Apple...")
        
        let (downloadedFileURL, response) = try await URLSession.shared.download(from: .anisetteLibraries)
        defer { try? FileManager.default.removeItem(at: downloadedFileURL) }
        
        // A failed download doesn't throw on its own, so an error page would reach the unzip step and fail as a missing file.
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        try FileManager.default.createDirectory(at: librariesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let temporaryDirectory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: librariesDirectory, create: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        
        let archivedLibraryPaths = AnisetteConstants.Libraries.requiredNames.map { "lib/arm64-v8a/" + $0 } // AnisetteKit emulates an ARM64 CPU.
        
        // FileManager.unzipArchive() can't unzip this since it contains case-insensitive duplicates (e.g. -QQ.xml and -Qq.xml).
        // Instead, use the system unzip, and only extract the two libraries we need.
        let arguments = ["-o", "-j", "-q", downloadedFileURL.path] + archivedLibraryPaths + ["-d", temporaryDirectory.path]
        _ = try await Process.launchAndWait(.unzip, arguments: arguments, environment: [:])
        
        for libraryName in AnisetteConstants.Libraries.requiredNames
        {
            let extractedLibraryURL = temporaryDirectory.appendingPathComponent(libraryName)
            let destinationURL = librariesDirectory.appendingPathComponent(libraryName)
            
            // Replacing rather than copying means an interrupted run can't leave a half-written library behind.
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: extractedLibraryURL)
        }
    }
    
    func makeAnisetteData(for identifier: UUID) async throws -> ALTAnisetteData
    {
        // AnisetteKit's default provider crashes AltServer. It also runs the downloaded libraries
        // as real code, which our security settings don't allow, so always use the emulated provider.
        let client = try AnisetteClient(provisioningDir: FileManager.default.anisetteDirectory,
                                        provider: UnicornAnisetteDataProvider(),
                                        libraryDirectoryResolver: { FileManager.default.anisetteLibrariesDirectory })
        
        // Apple rejects AnisetteKit's default localUserID because every one of its users shares it.
        let identifierBytes = withUnsafeBytes(of: identifier.uuid) { Data($0) } // The UUID's raw bytes.
        let localUserID = SHA256.hash(data: identifierBytes).map { String(format: "%02X", $0) }.joined() // Apple expects 64 uppercase hex characters.
        
        var headers = AnisetteRequestHeaders()
        headers.localUserID = localUserID
        
        let (responseHeaders, provisioningData) = try await client.getAnisetteData(identifier: identifier, headers: headers)
        
        if let provisioningData
        {
            Logger.main.notice("Provisioned new anisette identity (\(provisioningData.count) bytes).")
        }
        
        guard let machineID = responseHeaders[AnisetteConstants.Headers.machineID] else { throw AnisetteError.missingValue("machineID") }
        guard let oneTimePassword = responseHeaders[AnisetteConstants.Headers.oneTimePassword] else { throw AnisetteError.missingValue("oneTimePassword") }
        guard let routingInfoString = responseHeaders[AnisetteConstants.Headers.routingInfo], let routingInfo = UInt64(routingInfoString) else {
            throw AnisetteError.missingValue("routingInfo")
        }
        
        return ALTAnisetteData(machineID: machineID,
                               oneTimePassword: oneTimePassword,
                               localUserID: localUserID,
                               routingInfo: routingInfo,
                               deviceUniqueIdentifier: identifier.uuidString.uppercased(),
                               deviceSerialNumber: AnisetteConstants.defaultSerialNumber,
                               deviceDescription: client.clientInfo,
                               date: Date(),
                               locale: .current,
                               timeZone: .current)
    }
}
