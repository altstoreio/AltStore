//
//  OnDeviceClient.swift
//  AltStore
//
//  Created by Caroline Moore on 8/12/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import IDevice
import AltStoreCore
import AltSign

/// A client for the on-device RSD services, created from a pairing file.
/// Holds no live connection: every operation builds a fresh tunnel, does its work, and frees every handle before returning.
final class OnDeviceClient
{
    private static let tunnelHost = "10.7.0.1"
    private static let tunnelPort: UInt16 = 49152
    
    private let pairingFileData: Data
    
    // idevice calls block until they finish, so they all run on this background queue
    // one at a time (across every client), so there are never two tunnels open at once.
    private static let queue = DispatchQueue(label: "io.altstore.on-device-client", qos: .userInitiated)
    
    init(pairingFile: Data) throws
    {
        guard let record = try? PropertyListSerialization.propertyList(from: pairingFile, options: [], format: nil) as? [String: Any]
        else { throw OnDeviceError.invalidPairingFile() }
        
        // Same discriminator minimuxer used: `private_key` = RP record (RSD, iOS 17+),
        // `UDID` = classic lockdown record — supported starting in Phase 4.
        guard record["private_key"] != nil else
        {
            if record["UDID"] != nil { throw OnDeviceError.unsupportedPairingFile() }
            throw OnDeviceError.invalidPairingFile()
        }
        
        self.pairingFileData = pairingFile
    }
    
    func installApp(ipaURL: URL, bundleID: String, progress: Progress) async throws
    {
        try await self.perform {
            // 1. Stage the .ipa on the device via AFC.
            let ipaData = try Data(contentsOf: ipaURL)
            let stagingPath = "/PublicStaging/\(bundleID).ipa"
            
            Logger.sideload.notice("Transferring \(bundleID, privacy: .public) to device...")
            
            try self.withService(.afc) { afc in
                var file: OpaquePointer?
                try self.check(afc_file_open(afc, stagingPath, AfcWrOnly, &file))
                defer { if let error = afc_file_close(file) { idevice_error_free(error) } }
                
                try ipaData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                    try self.check(afc_file_write(file, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count))
                }
            }
            
            progress.completedUnitCount += 50
            
            // 2. Install from the staged path.
            Logger.sideload.notice("Installing \(bundleID, privacy: .public)...")
            
            try self.withService(.installationProxy) { proxy in
                try self.check(installation_proxy_install(proxy, stagingPath, nil))
            }
            
            progress.completedUnitCount += 50
        }
    }
    
    func removeApp(bundleID: String) async throws
    {
        try await self.perform {
            try self.withService(.installationProxy) { proxy in
                try self.check(installation_proxy_uninstall(proxy, bundleID, nil))
            }
        }
    }
    
    func installProvisioningProfile(_ data: Data) async throws
    {
        try await self.perform {
            try self.withService(.misagent) { misagent in
                try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                    try self.check(misagent_install(misagent, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count))
                }
            }
        }
    }
    
    func installedProvisioningProfiles() async throws -> [ALTProvisioningProfile]
    {
        try await self.perform {
            try self.withService(.misagent) { misagent in
                // Parallel arrays: profiles[i] is lengths[i] bytes of raw PKCS#7 profile data.
                var profiles: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
                var lengths: UnsafeMutablePointer<Int>?
                var count: UInt = 0
                
                try self.check(misagent_copy_all(misagent, &profiles, &lengths, &count))
                defer { misagent_free_profiles(profiles, lengths, Int(count)) }
                
                var result: [ALTProvisioningProfile] = []
                
                for i in 0 ..< Int(count)
                {
                    guard let bytes = profiles?[i], let length = lengths?[i] else { continue }
                    
                    let data = Data(bytes: bytes, count: Int(length)) // Copies, so `result` outlives the free above.
                    if let profile = ALTProvisioningProfile(data: data) { result.append(profile) }
                }
                
                return result
            }
        }
    }
    
    func removeProvisioningProfile(_ profile: ALTProvisioningProfile) async throws
    {
        try await self.perform {
            try self.withService(.misagent) { misagent in
                // Lowercased to match minimuxer's behavior — until an uppercase
                // ProfileID is confirmed working on-device (design doc risk #2).
                try self.check(misagent_remove(misagent, profile.uuid.uuidString.lowercased()))
            }
        }
    }
}

private extension OnDeviceClient
{
    enum Service
    {
        case afc
        case installationProxy
        case misagent
    }
    
    // Work runs to completion once queued — cancellation isn't observed (same as Minimuxer).
    func perform<T>(_ work: @escaping () throws -> T) async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
    
    func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?) throws
    {
        guard let error else { return }
        throw OnDeviceError.serviceFailed(ffiError: error) // Factory extracts code/message + frees.
    }
    
    // One fresh tunnel + service client per call (Phase 0b: create ≈100ms — noise per op).
    func withService<T>(_ service: Service, _ body: (OpaquePointer) throws -> T) throws -> T
    {
        // 1. Parse the pairing file. tunnel_create_rppairing only borrows it, so we free it ourselves.
        var pairingFile: OpaquePointer? // Use OpaquePointer because we can't import expected type 'RpPairingFileHandle'
        let parseError = self.pairingFileData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            rp_pairing_file_from_bytes(buffer.bindMemory(to: UInt8.self).baseAddress, UInt(buffer.count), &pairingFile)
        }
        if let parseError
        {
            throw OnDeviceError.invalidPairingFile(ffiError: parseError)
        }
        defer { rp_pairing_file_free(pairingFile) }
        
        // 2. Open the encrypted tunnel + RSD handshake through the loopback VPN.
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.tunnelPort.bigEndian
        inet_pton(AF_INET, Self.tunnelHost, &address.sin_addr)
        
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        let connectError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: idevice_sockaddr.self, capacity: 1) { addressPointer in
                tunnel_create_rppairing(addressPointer, idevice_socklen_t(MemoryLayout<sockaddr_in>.size),
                                        Self.tunnelHost, pairingFile, nil, nil, &adapter, &handshake)
            }
        }
        if let connectError
        {
            throw OnDeviceError.connectionFailed(ffiError: connectError)
        }
        defer
        {
            rsd_handshake_free(handshake)
            adapter_free(adapter)
        }
        
        // 3. Connect the requested service, run the work, then free everything in reverse order.
        var client: OpaquePointer?
        switch service
        {
        case .afc: try self.check(afc_client_connect_rsd(adapter, handshake, &client))
        case .installationProxy: try self.check(installation_proxy_connect_rsd(adapter, handshake, &client))
        case .misagent: try self.check(misagent_connect_rsd(adapter, handshake, &client))
        }
        defer
        {
            switch service
            {
            case .afc: afc_client_free(client)
            case .installationProxy: installation_proxy_client_free(client)
            case .misagent: misagent_client_free(client)
            }
        }
        
        return try body(client!)
    }
}

extension OnDeviceError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = OnDeviceError
        
        case invalidPairingFile
        case unsupportedPairingFile
        case connectionFailed
        case serviceFailed
    }
    
    static func invalidPairingFile(ffiError: UnsafeMutablePointer<IdeviceFfiError>? = nil, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .invalidPairingFile, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func unsupportedPairingFile(file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .unsupportedPairingFile, sourceFile: file, sourceLine: line)
    }
    
    static func connectionFailed(ffiError: UnsafeMutablePointer<IdeviceFfiError>?, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .connectionFailed, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func serviceFailed(ffiError: UnsafeMutablePointer<IdeviceFfiError>?, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .serviceFailed, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
}

// MARK: Errors

struct OnDeviceError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var ffiCode: Int?
    
    @UserInfoValue
    var ffiReason: String?
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    fileprivate init(code: Code, ffiError: UnsafeMutablePointer<IdeviceFfiError>? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil)
    {
        self.code = code
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        
        if let ffiError
        {
            self.ffiCode = Int(ffiError.pointee.code)
            
            if let message = ffiError.pointee.message
            {
                self.ffiReason = String(cString: message)
            }
            
            idevice_error_free(ffiError)
        }
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .invalidPairingFile: return NSLocalizedString("AltStore couldn’t read the device pairing file.", comment: "")
        case .unsupportedPairingFile: return NSLocalizedString("This pairing file isn’t supported by this version of AltStore.", comment: "")
        case .connectionFailed: return NSLocalizedString("AltStore couldn’t connect to this device.", comment: "")
        case .serviceFailed: return NSLocalizedString("AltStore couldn’t communicate with this device.", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .invalidPairingFile, .unsupportedPairingFile:
            return NSLocalizedString("Pair your device with AltServer again to generate a new pairing file.", comment: "")
        case .connectionFailed:
            return NSLocalizedString("Make sure the VPN is connected, then try again.", comment: "")
        case .serviceFailed:
            return nil
        }
    }
}
