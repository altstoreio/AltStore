//
//  AnisetteVirtualMachine.swift
//  AltServer
//

import Compression
import Foundation
import OSLog
import Virtualization

/// Generates anisette data locally by running Apple's ADI libraries inside a minimal Linux guest.
///
/// Those libraries are linked for 4KB pages and place executable code and writable data in the
/// same page, which cannot be mapped on Apple silicon because its pages are 16KB and the kernel
/// refuses write+execute mappings. A Linux guest gives them the 4KB pages they expect, so the
/// libraries run unmodified while the host keeps talking to a plain HTTP endpoint.
@available(macOS 13.0, *)
final class AnisetteVirtualMachine: NSObject
{
    static let shared = AnisetteVirtualMachine()
    
    private enum Constants
    {
        static let vsockPort: UInt32 = 6969
        static let sharedDirectoryTag = "anisette"
        static let connectionAttempts = 180
        static let connectionRetryDelay: TimeInterval = 0.5
        static let idleTimeout: TimeInterval = 5 * 60
        static let appleMusicAPK = URL(string: "https://apps.mzstatic.com/content/android-apple-music-apk/applemusic.apk")!
        static let adiLibraries = ["libstoreservicescore.so", "libCoreADI.so"]
    }
    
    enum Error: LocalizedError
    {
        case missingResource(String)
        case corruptKernel
        case missingADILibraries
        case guestUnavailable
        case invalidResponse
        
        var errorDescription: String? {
            switch self
            {
            case .missingResource(let name): return String(format: NSLocalizedString("AltServer is missing a required resource (%@).", comment: ""), name)
            case .corruptKernel: return NSLocalizedString("The anisette virtual machine's kernel could not be decompressed.", comment: "")
            case .missingADILibraries: return NSLocalizedString("Apple's device provisioning libraries could not be downloaded.", comment: "")
            case .guestUnavailable: return NSLocalizedString("The anisette virtual machine did not start in time.", comment: "")
            case .invalidResponse: return NSLocalizedString("The anisette virtual machine returned an invalid response.", comment: "")
            }
        }
    }
    
    private let queue = DispatchQueue(label: "com.rileytestut.AltServer.AnisetteVM")
    private let ioQueue = DispatchQueue(label: "com.rileytestut.AltServer.AnisetteVM.io")
    
    private var virtualMachine: VZVirtualMachine?
    private var isRunning = false
    private var pendingStartHandlers: [(Result<Void, Swift.Error>) -> Void] = []
    private var consoleBuffer = Data()
    
    /// Pipes close themselves when deallocated, taking the guest's console with them.
    private var consoleInput: Pipe?
    private var consoleOutput: Pipe?
    
    private var idleTimer: DispatchSourceTimer?
    private var observer: AnyObject? // VZVirtualMachine only holds its delegate weakly.
    
    private lazy var supportDirectory: URL = {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("AltServer/AnisetteVM", isDirectory: true)
    }()
    
    private var kernelURL: URL { self.supportDirectory.appendingPathComponent("Image") }
    
    /// Shared into the guest read-write: holds Apple's libraries plus the provisioning state that
    /// has to survive reboots, because re-provisioning repeatedly makes Apple distrust the machine.
    private var stateDirectory: URL { self.supportDirectory.appendingPathComponent("state", isDirectory: true) }
    
    private override init()
    {
        super.init()
    }
}

@available(macOS 13.0, *)
extension AnisetteVirtualMachine
{
    func requestAnisetteData(completion: @escaping (Result<ALTAnisetteData, Swift.Error>) -> Void)
    {
        self.queue.async { self.cancelIdleTimeout() }
        
        self.start { result in
            switch result
            {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.fetchAnisetteData(attemptsRemaining: Constants.connectionAttempts) { result in
                    self.queue.async { self.scheduleIdleTimeout() }
                    completion(result)
                }
            }
        }
    }
    
    func stop()
    {
        self.queue.async {
            self.cancelIdleTimeout()
            
            guard let virtualMachine = self.virtualMachine, virtualMachine.canStop else { return self.reset() }
            
            virtualMachine.stop { _ in }
            self.reset()
        }
    }
}

/// Kept separate from AnisetteVirtualMachine because Virtualization types can't appear in the
/// generated Objective-C header, which every non-private declaration ends up in.
@available(macOS 13.0, *)
private final class VirtualMachineObserver: NSObject, VZVirtualMachineDelegate
{
    private let didStop: (Swift.Error?) -> Void
    
    init(didStop: @escaping (Swift.Error?) -> Void)
    {
        self.didStop = didStop
        
        super.init()
    }
    
    func guestDidStop(_ virtualMachine: VZVirtualMachine)
    {
        self.didStop(nil)
    }
    
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Swift.Error)
    {
        self.didStop(error)
    }
}

@available(macOS 13.0, *)
private extension AnisetteVirtualMachine
{
    func start(completion: @escaping (Result<Void, Swift.Error>) -> Void)
    {
        self.queue.async {
            if self.isRunning
            {
                completion(.success(()))
                return
            }
            
            self.pendingStartHandlers.append(completion)
            guard self.pendingStartHandlers.count == 1 else { return } // A start is already in flight.
            
            do
            {
                try self.prepareResources()
                
                let observer = VirtualMachineObserver { [weak self] error in
                    if let error
                    {
                        Logger.main.error("Anisette virtual machine stopped with error. \(error.localizedDescription, privacy: .public)")
                    }
                    else
                    {
                        Logger.main.info("Anisette virtual machine stopped.")
                    }
                    
                    self?.reset()
                }
                
                let virtualMachine = VZVirtualMachine(configuration: try self.makeConfiguration(), queue: self.queue)
                virtualMachine.delegate = observer
                self.observer = observer
                self.virtualMachine = virtualMachine
                
                virtualMachine.start { result in
                    switch result
                    {
                    case .success:
                        Logger.main.info("Started anisette virtual machine.")
                        self.finishStarting(with: .success(()))
                        
                    case .failure(let error):
                        self.reset()
                        self.finishStarting(with: .failure(error))
                    }
                }
            }
            catch
            {
                self.finishStarting(with: .failure(error))
            }
        }
    }
    
    func finishStarting(with result: Result<Void, Swift.Error>)
    {
        let handlers = self.pendingStartHandlers
        self.pendingStartHandlers = []
        
        if case .success = result { self.isRunning = true }
        handlers.forEach { $0(result) }
    }
    
    func reset()
    {
        self.consoleOutput?.fileHandleForReading.readabilityHandler = nil
        self.consoleInput = nil
        self.consoleOutput = nil
        self.consoleBuffer.removeAll()
        
        self.virtualMachine = nil
        self.observer = nil
        self.isRunning = false
    }
    
    /// Nothing else needs the guest between installs, and it holds onto a few hundred megabytes.
    func scheduleIdleTimeout()
    {
        self.cancelIdleTimeout()
        
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now() + Constants.idleTimeout)
        timer.setEventHandler { [weak self] in
            Logger.main.info("Stopping idle anisette virtual machine.")
            self?.stop()
        }
        timer.resume()
        
        self.idleTimer = timer
    }
    
    func cancelIdleTimeout()
    {
        self.idleTimer?.cancel()
        self.idleTimer = nil
    }
    
    func makeConfiguration() throws -> VZVirtualMachineConfiguration
    {
        guard let initramfsURL = Bundle.main.url(forResource: "initramfs", withExtension: "cpio") else {
            throw Error.missingResource("initramfs.cpio")
        }
        
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = 2
        configuration.memorySize = 1024 * 1024 * 1024
        
        let bootLoader = VZLinuxBootLoader(kernelURL: self.kernelURL)
        bootLoader.initialRamdiskURL = initramfsURL
        bootLoader.commandLine = "console=hvc0 quiet"
        configuration.bootLoader = bootLoader
        
        let input = Pipe()
        let output = Pipe()
        self.consoleInput = input
        self.consoleOutput = output
        
        let console = VZVirtioConsoleDeviceSerialPortConfiguration()
        console.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: input.fileHandleForReading,
                                                              fileHandleForWriting: output.fileHandleForWriting)
        configuration.serialPorts = [console]
        self.observeConsole(output.fileHandleForReading)
        
        // The guest provisions itself directly with Apple, so it needs outbound access.
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        configuration.networkDevices = [network]
        
        let share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: self.stateDirectory, readOnly: false))
        let fileSystem = VZVirtioFileSystemDeviceConfiguration(tag: Constants.sharedDirectoryTag)
        fileSystem.share = share
        configuration.directorySharingDevices = [fileSystem]
        
        // vsock rather than TCP: the host reaches the guest without depending on how (or whether)
        // the NAT subnet happens to be routable, which VPN clients routinely break.
        configuration.socketDevices = [VZVirtioSocketDeviceConfiguration()]
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        
        try configuration.validate()
        return configuration
    }
    
    func observeConsole(_ fileHandle: FileHandle)
    {
        fileHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            self.queue.async {
                self.consoleBuffer.append(data)
                
                while let range = self.consoleBuffer.firstRange(of: Data("\n".utf8))
                {
                    let lineData = self.consoleBuffer.subdata(in: self.consoleBuffer.startIndex ..< range.lowerBound)
                    self.consoleBuffer.removeSubrange(self.consoleBuffer.startIndex ... range.lowerBound)
                    
                    guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { continue }
                    Logger.main.info("Anisette guest: \(line, privacy: .public)")
                }
            }
        }
    }
    
    /// The guest only starts listening once it has provisioned itself with Apple, which takes a
    /// while the very first time, so keep knocking rather than guessing how long to wait.
    func fetchAnisetteData(attemptsRemaining: Int, completion: @escaping (Result<ALTAnisetteData, Swift.Error>) -> Void)
    {
        self.queue.async {
            guard let socketDevice = self.virtualMachine?.socketDevices.first as? VZVirtioSocketDevice else {
                return completion(.failure(Error.guestUnavailable))
            }
            
            socketDevice.connect(toPort: Constants.vsockPort) { result in
                switch result
                {
                case .failure(let error):
                    guard attemptsRemaining > 0 else {
                        Logger.main.error("Anisette virtual machine never accepted a connection. \(error.localizedDescription, privacy: .public)")
                        return completion(.failure(Error.guestUnavailable))
                    }
                    
                    self.queue.asyncAfter(deadline: .now() + Constants.connectionRetryDelay) {
                        self.fetchAnisetteData(attemptsRemaining: attemptsRemaining - 1, completion: completion)
                    }
                    
                case .success(let connection):
                    // Reading blocks, so keep it off the queue the virtual machine runs on.
                    self.ioQueue.async {
                        defer { connection.close() }
                        
                        do
                        {
                            let response = try self.sendRequest(over: connection.fileDescriptor)
                            guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw Error.invalidResponse }
                            
                            let anisetteData = try ALTAnisetteData(anisetteServerResponse: json)
                            completion(.success(anisetteData))
                        }
                        catch
                        {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }
    
    func sendRequest(over fileDescriptor: Int32) throws -> Data
    {
        let request = Data("GET / HTTP/1.0\r\n\r\n".utf8)
        try request.withUnsafeBytes { buffer in
            guard write(fileDescriptor, buffer.baseAddress, buffer.count) == buffer.count else { throw Error.guestUnavailable }
        }
        
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while true
        {
            let count = read(fileDescriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            response.append(contentsOf: buffer[0 ..< count])
        }
        
        guard let separator = response.firstRange(of: Data("\r\n\r\n".utf8)) else { throw Error.invalidResponse }
        return response.subdata(in: separator.upperBound ..< response.endIndex)
    }
}

@available(macOS 13.0, *)
private extension AnisetteVirtualMachine
{
    func prepareResources() throws
    {
        try FileManager.default.createDirectory(at: self.stateDirectory, withIntermediateDirectories: true)
        
        if !FileManager.default.fileExists(atPath: self.kernelURL.path)
        {
            try self.extractKernel()
        }
        
        let libraryDirectory = self.stateDirectory.appendingPathComponent("lib/arm64-v8a", isDirectory: true)
        let hasLibraries = Constants.adiLibraries.allSatisfy { FileManager.default.fileExists(atPath: libraryDirectory.appendingPathComponent($0).path) }
        
        if !hasLibraries
        {
            try self.downloadADILibraries(to: libraryDirectory)
        }
    }
    
    /// The bundled kernel is an EFI zboot image: a PE wrapper around a gzip stream that
    /// VZLinuxBootLoader can't read, so unwrap it once into Application Support.
    func extractKernel() throws
    {
        guard let compressedURL = Bundle.main.url(forResource: "vmlinuz-virt", withExtension: nil) else {
            throw Error.missingResource("vmlinuz-virt")
        }
        
        let compressed = try Data(contentsOf: compressedURL)
        guard compressed.count > 0x20, compressed[4 ..< 8].elementsEqual(Data("zimg".utf8)) else { throw Error.corruptKernel }
        
        let payloadOffset = Int(compressed.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
        let payloadSize = Int(compressed.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
        guard payloadOffset > 0, payloadSize > 0, payloadOffset + payloadSize <= compressed.count else { throw Error.corruptKernel }
        
        let payload = compressed.subdata(in: payloadOffset ..< (payloadOffset + payloadSize))
        let kernel = try self.inflateGzip(payload)
        
        try FileManager.default.createDirectory(at: self.supportDirectory, withIntermediateDirectories: true)
        try kernel.write(to: self.kernelURL)
        
        Logger.main.info("Extracted anisette guest kernel (\(kernel.count) bytes).")
    }
    
    func inflateGzip(_ data: Data) throws -> Data
    {
        // Compression only speaks raw DEFLATE, so step over the gzip header ourselves.
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else { throw Error.corruptKernel }
        
        let flags = data[3]
        var offset = 10
        
        if flags & 0x04 != 0
        {
            guard offset + 2 <= data.count else { throw Error.corruptKernel }
            let extraLength = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        
        for mask in [UInt8(0x08), UInt8(0x10)] where flags & mask != 0
        {
            while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }
            offset += 1
        }
        
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count - 8 else { throw Error.corruptKernel }
        
        let deflated = data.subdata(in: (data.startIndex + offset) ..< (data.endIndex - 8))
        let expectedSize = Int(data.suffix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        
        var inflated = Data(count: expectedSize)
        let written = inflated.withUnsafeMutableBytes { destination in
            deflated.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          source.bindMemory(to: UInt8.self).baseAddress!, deflated.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        
        guard written == expectedSize else { throw Error.corruptKernel }
        return inflated
    }
    
    /// Apple's ADI libraries can't be redistributed, so they're pulled from the Apple Music
    /// Android package the same way every other anisette implementation does it.
    func downloadADILibraries(to directory: URL) throws
    {
        Logger.main.info("Downloading Apple's device provisioning libraries…")
        
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        
        let archiveURL = temporaryDirectory.appendingPathComponent("applemusic.apk")
        let archive = try Data(contentsOf: Constants.appleMusicAPK)
        try archive.write(to: archiveURL)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", "-j", archiveURL.path] + Constants.adiLibraries.map { "lib/arm64-v8a/\($0)" } + ["-d", temporaryDirectory.path]
        try process.run()
        process.waitUntilExit()
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        for library in Constants.adiLibraries
        {
            let source = temporaryDirectory.appendingPathComponent(library)
            guard FileManager.default.fileExists(atPath: source.path) else { throw Error.missingADILibraries }
            
            let destination = directory.appendingPathComponent(library)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: source, to: destination)
        }
        
        Logger.main.info("Downloaded Apple's device provisioning libraries.")
    }
}
