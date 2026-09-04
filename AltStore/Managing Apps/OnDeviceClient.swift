//
//  OnDeviceClient.swift
//  AltStore
//
//  Created by Caroline Moore on 8/12/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import Network
import IDevice
import AltStoreCore
import AltSign

/// Installs apps and manages provisioning profiles on this device itself, over the loopback VPN. Each operation opens and closes its own tunnel.
final class OnDeviceClient: Sendable
{
    private static let tunnelHost = "10.7.0.1" // The address LocalDevVPN assigns to this device (must match the VPN's configured address).
    private static let tunnelPort: UInt16 = 49152 // The fixed port iOS's pairing service listens on.
    
    private static let tunnelAddress: sockaddr_in = {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = tunnelPort.bigEndian
        inet_pton(AF_INET, tunnelHost, &address.sin_addr)
        return address
    }()
    
    private let pairingFileData: Data
    
    // idevice calls block their thread, so they all run on this shared background queue one at a time.
    private static let queue = DispatchQueue(label: "io.altstore.on-device-client", qos: .userInitiated)
    
    init(pairingFile: Data) throws
    {
        let record: [String: Any]?
        do
        {
            record = try PropertyListSerialization.propertyList(from: pairingFile, options: [], format: nil) as? [String: Any]
        }
        catch
        {
            Logger.sideload.error("Failed to parse pairing file: \(error.localizedDescription, privacy: .public)")
            throw OnDeviceError.invalidPairingFile()
        }
        
        // RP-pairing records (iOS 17+) contain `private_key` (and older lockdown records aren't supported yet).
        guard let record, record["private_key"] != nil else { throw OnDeviceError.invalidPairingFile() }
        
        self.pairingFileData = pairingFile
    }
    
    func installApp(ipaURL: URL, bundleIdentifier: String, progress: Progress) async throws
    {
        progress.totalUnitCount = 100
        
        let stagingPath = "/PublicStaging/\(bundleIdentifier).ipa"
        
        Logger.sideload.notice("Transferring \(bundleIdentifier, privacy: .public) to device...")
        
        // First, copy the .ipa into the device's staging folder.
        try await self.perform(withService: .afc) { afc in
            let ipaData = try Data(contentsOf: ipaURL, options: .mappedIfSafe)
            
            var file: OpaquePointer?
            if let openError = afc_file_open(afc, stagingPath, AfcWrOnly, &file)
            {
                throw OnDeviceError.serviceFailed(ffiError: openError)
            }
            defer
            {
                // Close the file, and since we can't throw, just log any error and free it.
                if let closeError = afc_file_close(file)
                {
                    let error = OnDeviceError.serviceFailed(ffiError: closeError)
                    Logger.sideload.error("Failed to close staged .ipa on device: \(error.underlyingError?.localizedDescription ?? "unknown error", privacy: .public)")
                }
            }
            
            try ipaData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let bytes = buffer.bindMemory(to: UInt8.self)
                if let writeError = afc_file_write(file, bytes.baseAddress, bytes.count)
                {
                    throw OnDeviceError.serviceFailed(ffiError: writeError)
                }
            }
        }
        
        progress.completedUnitCount += 50
        
        Logger.sideload.notice("Installing \(bundleIdentifier, privacy: .public)...")
        
        // Then, ask the device to install the app from that staged file.
        try await self.perform(withService: .installationProxy) { proxy in
            if let installError = installation_proxy_install(proxy, stagingPath, nil)
            {
                throw OnDeviceError.serviceFailed(ffiError: installError)
            }
        }
        
        progress.completedUnitCount += 50
    }
    
    func removeApp(bundleIdentifier: String) async throws
    {
        try await self.perform(withService: .installationProxy) { proxy in
            if let uninstallError = installation_proxy_uninstall(proxy, bundleIdentifier, nil)
            {
                throw OnDeviceError.serviceFailed(ffiError: uninstallError)
            }
        }
    }
    
    func installProvisioningProfile(_ profile: ALTProvisioningProfile) async throws
    {
        try await self.perform(withService: .misagent) { misagent in
            try profile.data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let bytes = buffer.bindMemory(to: UInt8.self)
                if let installError = misagent_install(misagent, bytes.baseAddress, bytes.count)
                {
                    throw OnDeviceError.serviceFailed(ffiError: installError)
                }
            }
        }
    }
    
    func installedProvisioningProfiles() async throws -> [ALTProvisioningProfile]
    {
        try await self.perform(withService: .misagent) { misagent in
            // misagent hands back two arrays: the raw bytes of each installed profile, and the length of each one.
            var rawProfiles: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
            var lengths: UnsafeMutablePointer<Int>?
            var count = 0
            
            if let copyError = misagent_copy_all(misagent, &rawProfiles, &lengths, &count)
            {
                throw OnDeviceError.serviceFailed(ffiError: copyError)
            }
            defer { misagent_free_profiles(rawProfiles, lengths, count) }
            
            var profiles: [ALTProvisioningProfile] = []
            
            for i in 0 ..< count
            {
                guard let bytes = rawProfiles?[i], let length = lengths?[i] else { continue }
                
                // Copy profiles into Data so the bytes stay valid after they're freed in the defer above.
                let data = Data(bytes: bytes, count: length)
                if let profile = ALTProvisioningProfile(data: data)
                {
                    profiles.append(profile)
                }
            }
            
            return profiles
        }
    }
    
    func removeProvisioningProfile(_ profile: ALTProvisioningProfile) async throws
    {
        try await self.perform(withService: .misagent) { misagent in
            if let removeError = misagent_remove(misagent, profile.uuid.uuidString.lowercased()) // Lowercase required, confirmed on device.
            {
                throw OnDeviceError.serviceFailed(ffiError: removeError)
            }
        }
    }
    
    // Returns false when the VPN tunnel is down, the network is unavailable, or the device isn't responding.
    // Can block while waiting for a response, so it's async to keep callers off the main thread.
    static func isReachable() async -> Bool
    {
        // Give up if the device hasn't responded in a second. Normally connects in a few ms.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 1
        
        let isReachable = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(tunnelHost), port: NWEndpoint.Port(integerLiteral: tunnelPort), using: NWParameters(tls: nil, tcp: tcpOptions))
            let queue = DispatchQueue(label: "io.altstore.reachability-probe")
            
            // We can only resume the continuation once, so stop listening for state changes before we do.
            @Sendable func finish(_ result: Bool)
            {
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }
            
            connection.stateUpdateHandler = { (state) in
                switch state
                {
                case .ready: finish(true)
                case .waiting(let error):
                    // https://developer.apple.com/documentation/network/nwconnection/state-swift.enum/waiting(_:)
                    // Waiting means "no route to the device right now." Signals VPN is off.
                    Logger.sideload.error("Couldn't reach the device. \(error.localizedDescription, privacy: .public)")
                    finish(false)
                    
                case .failed(let error):
                    Logger.sideload.error("Reachability probe failed. \(error.localizedDescription, privacy: .public)")
                    finish(false)
                    
                default: break // Still connecting (.setup/.preparing), or the .cancelled we trigger in finish().
                }
            }
            
            connection.start(queue: queue)
        }
        
        guard isReachable else
        {
            Logger.sideload.error("Device not reachable at \(tunnelHost, privacy: .public) — VPN tunnel likely down.")
            return false
        }
        return true
    }
}

private extension OnDeviceClient
{
    enum Service
    {
        case afc                // moves files
        case installationProxy  // installs/removes apps
        case misagent           // manages provisioning profiles
    }
    
    // Runs a device session on the shared background queue, suspending until it finishes. Sessions always run to completion.
    func perform<T>(withService service: Service, _ body: @escaping (OpaquePointer) throws -> T) async throws -> T
    {
        // Make sure the device is reachable (Wi-Fi + VPN on) before we touch the tunnel. (This also means a socket error later can't be blamed on the VPN.)
        guard await Self.isReachable() else { throw OperationError.vpnNotConnected() }

        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                let result = Result { try self._perform(withService: service, body) }
                continuation.resume(with: result)
            }
        }
    }
    
    // One complete conversation with the device: opens a new tunnel, connects the requested service, runs the work, and closes everything before returning.
    func _perform<T>(withService service: Service, _ body: (OpaquePointer) throws -> T) throws -> T
    {
        // 1. Convert our pairing file data to the form idevice needs.
        var pairingFile: OpaquePointer?
        
        let parseError = self.pairingFileData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            return rp_pairing_file_from_bytes(bytes.baseAddress, UInt(bytes.count), &pairingFile)
        }
        if let parseError
        {
            throw OnDeviceError.invalidPairingFile(ffiError: parseError)
        }
        defer { rp_pairing_file_free(pairingFile) } // tunnel_create_rppairing only borrows the file, so we have to free it ourselves.
        
        // 2. Open the encrypted tunnel to the device through the VPN and perform the RSD handshake.
        var address = Self.tunnelAddress
        let addressSize = idevice_socklen_t(MemoryLayout<sockaddr_in>.size)
        
        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        
        let connectError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: idevice_sockaddr.self, capacity: 1) { address in
                tunnel_create_rppairing(address, addressSize, Self.tunnelHost, pairingFile, nil, nil, &adapter, &handshake) // The two nils signal idevice to use its default PIN (000000).
            }
        }
        if let connectError
        {
            // The device dropping our connection like this means it revoked its pairing trust (confirmed on device).
            let socketErrorCode: Int32 = 1
            let connectionResetSubCode: Int32 = 54
            if connectError.pointee.code == socketErrorCode, connectError.pointee.sub_code == connectionResetSubCode
            {
                throw OnDeviceError.pairingNotTrusted(ffiError: connectError)
            }
            throw OnDeviceError.connectionFailed(ffiError: connectError)
        }
        defer
        {
            rsd_handshake_free(handshake)
            adapter_free(adapter)
        }
        
        // 3. Connect the requested service, run the work, then free everything.
        var client: OpaquePointer?
        
        let serviceError: UnsafeMutablePointer<IdeviceFfiError>?
        switch service
        {
        case .afc: serviceError = afc_client_connect_rsd(adapter, handshake, &client)
        case .installationProxy: serviceError = installation_proxy_connect_rsd(adapter, handshake, &client)
        case .misagent: serviceError = misagent_connect_rsd(adapter, handshake, &client)
        }
        if let serviceError
        {
            throw OnDeviceError.serviceFailed(ffiError: serviceError)
        }
        
        guard let client else { throw OperationError.unknown() }
        
        defer
        {
            switch service
            {
            case .afc: afc_client_free(client)
            case .installationProxy: installation_proxy_client_free(client)
            case .misagent: misagent_client_free(client)
            }
        }
        
        return try body(client)
    }
}

// MARK: - Errors

extension OnDeviceError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = OnDeviceError
        
        case invalidPairingFile = 0
        case pairingNotTrusted = 1
        case connectionFailed = 2
        case serviceFailed = 3
    }
    
    static func invalidPairingFile(ffiError: UnsafeMutablePointer<IdeviceFfiError>? = nil, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .invalidPairingFile, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func pairingNotTrusted(ffiError: UnsafeMutablePointer<IdeviceFfiError>?, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .pairingNotTrusted, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func connectionFailed(ffiError: UnsafeMutablePointer<IdeviceFfiError>?, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .connectionFailed, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func serviceFailed(ffiError: UnsafeMutablePointer<IdeviceFfiError>?, file: String = #fileID, line: UInt = #line) -> OnDeviceError {
        OnDeviceError(code: .serviceFailed, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
}

struct OnDeviceError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    // The original idevice error, stored under Apple's standard key so the Error Log shows it.
    @UserInfoValue(key: NSUnderlyingErrorKey)
    var underlyingError: NSError? = nil
    
    var sourceFile: String?
    var sourceLine: UInt?
    
    fileprivate init(code: Code, ffiError: UnsafeMutablePointer<IdeviceFfiError>? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil)
    {
        self.code = code
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        
        if let ffiError
        {
            // Bundle everything idevice told us into one underlying error.
            var userInfo: [String: Any] = ["subCode": Int(ffiError.pointee.sub_code)]
            
            if let message = ffiError.pointee.message
            {
                userInfo[NSLocalizedDescriptionKey] = String(cString: message)
            }
            
            self.underlyingError = NSError(domain: "IdeviceError", code: Int(ffiError.pointee.code), userInfo: userInfo)
            
            idevice_error_free(ffiError) // Free the C error.
        }
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .invalidPairingFile: return String(localized: "AltStore couldn’t read this device’s pairing.")
        case .pairingNotTrusted: return String(localized: "This device is no longer paired with AltStore.")
        case .connectionFailed: return String(localized: "AltStore couldn’t connect to this device.")
        case .serviceFailed: return String(localized: "AltStore couldn’t communicate with this device.")
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .invalidPairingFile, .pairingNotTrusted: return String(localized: "Pair this device again from Remote AltServer in AltStore’s Settings.")
        case .connectionFailed: return String(localized: "Make sure the VPN is connected, then try again.")
        case .serviceFailed: return nil
        }
    }
}
