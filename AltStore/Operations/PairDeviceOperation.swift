//
//  PairDeviceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import BackgroundTasks

import AltStoreCore

import IDevice

extension PairError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = PairError
        
        case unknown
        case timedOut
    }
    
    static func unknown(ffiError: UnsafeMutablePointer<IdeviceFfiError>? = nil, file: String = #fileID, line: UInt = #line) -> PairError {
        PairError(code: .unknown, ffiError: ffiError, sourceFile: file, sourceLine: line)
    }
    
    static func timedOut(file: String = #fileID, line: UInt = #line) -> PairError {
        PairError(code: .timedOut, sourceFile: file, sourceLine: line)
    }
}

struct PairError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    // The original idevice error, stored under Apple's standard key so the Error Log shows it.
    @UserInfoValue(key: NSUnderlyingErrorKey)
    var ffiUnderlyingError: NSError? = nil
    
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
            
            self.ffiUnderlyingError = NSError(domain: "IdeviceError", code: Int(ffiError.pointee.code), userInfo: userInfo)
            
            idevice_error_free(ffiError) // Free the C error.
        }
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown: return String(localized: "An unknown error occurred.")
        case .timedOut: return String(localized: "iOS ended pairing before it finished.")
        }
    }
}

@objc(PairDeviceOperation) @available(iOS 27, *)
class PairDeviceOperation: ResultOperation<Void>, @unchecked Sendable
{
    let context: OperationContext
    
    // idevice's handshake blocks its thread, so it runs on this background queue.
    private let pairingQueue = DispatchQueue(label: "io.altstore.PairDeviceOperation", qos: .userInitiated)
    
    private var task: Task<Void, Never>?
    private var service: NetService?
    private var listener: PairingListener?
    
    override var isExtendedBackgroundTask: Bool {
        return true
    }

    init(context: OperationContext)
    {
        self.context = context
    }

    override func main()
    {
        super.main()

        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }

        self.task = Task<Void, Never> {
            do
            {
                Logger.sideload.notice("Pairing device with AltStore...")
                
                let taskID = "com.rileytestut.AltStore.PairDevice" + "." + UUID().uuidString // Unique Task ID per pairing attempt (to avoid crash when registering duplicate task ID)
                let title = String(localized: "Pairing AltStore…")
                let subtitle = String(localized: "Privacy & Security → Developer Mode")
                
                try await BGTaskScheduler.shared.startBackgroundTask(identifier: taskID, title: title, subtitle: subtitle) { task in
                    do
                    {
                        let data = try await self.pairDevice()
                        Keychain.shared.devicePairingFile = data
                        
                        task.updateTitle(String(localized: "Pairing Complete"), subtitle: String(localized: "Please return to AltStore."))
                    }
                    catch
                    {
                        task.updateTitle(String(localized: "Pairing Failed"), subtitle: error.localizedDescription)
                        throw error
                    }
                } expiration: {
                    self.finish(.failure(PairError.timedOut()))
                    self.cancel()
                }
                
                Logger.sideload.notice("Successfully paired device with AltStore!")
                
                self.finish(.success(()))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
    
    override func cancel()
    {
        super.cancel()
        
        self.task?.cancel()
        self.listener?.invalidate()
    }
    
    override func finish(_ result: Result<Void, any Error>)
    {
        super.finish(result)
        
        self.service?.stop()
        self.listener?.invalidate()
    }
}

@available(iOS 27, *)
private extension PairDeviceOperation
{
    func pairDevice() async throws -> Data
    {
        // Create the identity we'll pair as, plus the Bonjour details Settings uses to find it.
        var handle: OpaquePointer?
        var serviceID: UnsafeMutablePointer<CChar>?
        var txtData: UnsafeMutablePointer<UInt8>?
        var txtLength: UInt = 0
        
        if let error = pairable_host_new("AltStore", "Mac16,11", &handle, &serviceID, &txtData, &txtLength) // Model is a 2025 Mac mini.
        {
            throw PairError.unknown(ffiError: error)
        }
        defer {
            pairable_host_free(handle)
            idevice_string_free(serviceID)
            idevice_data_free(txtData, txtLength)
        }
        
        guard let serviceID, let txtData else { throw PairError.unknown() }
        
        let serviceIdentifier = String(cString: serviceID)
        let txtRecord = try Self.txtRecord(fromPlist: Data(bytes: txtData, count: Int(txtLength)))
        
        // Open the listening socket, then publish it over Bonjour so the device can find us.
        let listener = try PairingListener()
        self.listener = listener
        
        let service = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: serviceIdentifier, port: Int32(listener.port))
        service.setTXTRecord(NetService.data(fromTXTRecord: txtRecord))
        service.publish()
        self.service = service
        
        // Open Settings app for user's convenience.
        let settingsRootDeepLink = URL(string: "App-Prefs:")!
        await MainActor.run { UIApplication.shared.open(settingsRootDeepLink, options: [:]) }
        
        // Wait for the device to connect, then run the pairing handshake over that connection.
        let connectionFD = try await self.onPairingQueue { try listener.waitForConnection() }
        let data = try await self.performHandshake(handle: handle, connectionFD: connectionFD)
        
        // Validate data is in correct format.
        _ = try FetchPairingFileOperation.PairingFile(data: data)
        
        return data
    }

    func performHandshake(handle: OpaquePointer?, connectionFD: Int32) async throws -> Data
    {
        try await self.onPairingQueue {
            defer { close(connectionFD) } // idevice duplicates the socket, so we still own this one.
            
            var pairingFile: OpaquePointer?
            if let error = pairable_host_handshake(handle, connectionFD, ALTPairingPinCallback, nil, &pairingFile)
            {
                throw PairError.unknown(ffiError: error)
            }
            defer { rp_pairing_file_free(pairingFile) }
            
            var bytes: UnsafeMutablePointer<UInt8>?
            var length: UInt = 0
            if let error = rp_pairing_file_to_bytes(pairingFile, &bytes, &length)
            {
                throw PairError.unknown(ffiError: error)
            }
            defer { idevice_data_free(bytes, length) }
            
            guard let bytes else { throw PairError.unknown() }
            return Data(bytes: bytes, count: Int(length))
        }
    }
    
    // Runs blocking work on the pairing queue, suspending until it finishes.
    func onPairingQueue<T>(_ work: @escaping () throws -> T) async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            self.pairingQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
    
    static func txtRecord(fromPlist data: Data) throws -> [String: Data]
    {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            throw PairError.unknown()
        }
        
        return plist.mapValues { Data($0.utf8) } // NetService wants the TXT values as Data.
    }
}

// A TCP listener that hands back the file descriptor of the connection it accepts.
// idevice's handshake needs one, and Apple's networking APIs never expose it.
@available(iOS 27, *)
private final class PairingListener: @unchecked Sendable
{
    let port: UInt16
    
    private let fileDescriptor: Int32
    
    private var isInvalidated = false
    private let lock = NSLock()
    
    init() throws
    {
        let listenerFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenerFD >= 0 else { throw PairError.unknown() }
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0) // Any local address. Settings doesn't connect over localhost even though it's the same device (confirmed on device).
        address.sin_port = 0 // Let the OS choose a free port.
        
        let addressSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenerFD, $0, addressSize) }
        }
        
        guard didBind == 0, listen(listenerFD, 1) == 0 else {
            close(listenerFD)
            throw PairError.unknown()
        }
        
        // Read back the port the OS assigned.
        var boundAddress = sockaddr_in()
        var boundSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didReadPort = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listenerFD, $0, &boundSize) }
        }
        
        guard didReadPort == 0 else {
            close(listenerFD)
            throw PairError.unknown()
        }
        
        self.fileDescriptor = listenerFD
        self.port = UInt16(bigEndian: boundAddress.sin_port)
    }
    
    // Blocks until a device connects, or throws once the listener is invalidated.
    func waitForConnection() throws -> Int32
    {
        let connectionFD = accept(self.fileDescriptor, nil, nil)
        guard connectionFD >= 0 else { throw PairError.unknown() }
        
        // If this connection dies, a write to it would kill the entire app, so make any writes fail with a normal error instead.
        var noSigPipe: Int32 = 1
        setsockopt(connectionFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        
        return connectionFD
    }
    
    func invalidate()
    {
        // cancel() and finish() can both call from different threads, so make sure we only clean up once.
        self.lock.lock()
        defer { self.lock.unlock() }
        
        guard !self.isInvalidated else { return }
        self.isInvalidated = true
        
        close(self.fileDescriptor)
    }
}

@available(iOS 27, *)
private let ALTPairingPinCallback: PairableHostPinCb = { cPin, ctx in
    guard let cPin else { return }
    
    let pin = String(cString: cPin)
    Logger.main.info("Pairing device with PIN \(pin, privacy: .public)...")
}
