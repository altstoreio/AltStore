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
import AltSign
import Roxas

import IDevice

@available(iOS 27, *)
private struct PairingReadyMessage: NotificationCenter.AsyncMessage
{
    typealias Subject = PairDeviceOperation
    
    let serviceID: String
    let port: Int
    let txtRecord: [String: Data]
}

@available(iOS 27, *)
private extension NotificationCenter.MessageIdentifier where Self == NotificationCenter.BaseMessageIdentifier<PairingReadyMessage>
{
    static var pairingReady: Self { .init() }
}

extension PairError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = PairError
        
        case unknown
        case timedOut
    }
    
    static func unknown(failureReason: String = String(localized: "An unknown error occurred."), file: String = #fileID, line: UInt = #line) -> PairError {
        PairError(code: .unknown, errorFailureReason: failureReason, sourceFile: file, sourceLine: line)
    }
    
    static func timedOut(file: String = #fileID, line: UInt = #line) -> PairError {
        PairError(code: .timedOut, errorFailureReason: String(localized: "iOS ended the pairing session before pairing completed."), sourceFile: file, sourceLine: line)
    }
}

struct PairError: ALTLocalizedError
{
    let code: Code
    
    var errorFailureReason: String
    
    var errorTitle: String?
    var errorFailure: String?
    var sourceFile: String?
    var sourceLine: UInt?
}

@objc(PairDeviceOperation) @available(iOS 27, *)
class PairDeviceOperation: ResultOperation<Void>, @unchecked Sendable
{
    let context: OperationContext
    
    private var task: Task<Void, Never>?
    private var service: NetService?
    
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
    }
    
    override func finish(_ result: Result<Void, any Error>)
    {
        super.finish(result)
        
        self.service?.stop()
    }
}

@available(iOS 27, *)
private extension PairDeviceOperation
{
    func pairDevice() async throws -> Data
    {
        let outputURL = FileManager.default.uniqueTemporaryURL().appendingPathExtension("plist")
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        var output = RpPairingHostResult()
        
        // Publish Bonjour service once we receive pairing callback with required info
        let observer = NotificationCenter.default.addObserver(of: self, for: .pairingReady) { message in
            let txtRecordData = NetService.data(fromTXTRecord: message.txtRecord)
            
            let service = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: message.serviceID, port: Int32(message.port))
            service.setTXTRecord(txtRecordData)
            service.publish()
            self.service = service
        }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
            rp_pairing_host_result_free(&output)
            
            do { try FileManager.default.removeItem(at: outputURL) }
            catch { Logger.main.error("Failed to remove cached Pairing File. \(error.localizedDescription, privacy: .public)") }
        }
        
        // Open Settings app for user's convenience.
        let settingsRootDeepLink = URL(string: "App-Prefs:")!
        await MainActor.run { UIApplication.shared.open(settingsRootDeepLink, options: [:]) }
        
        // Start pairing process (must be started after we are listening for .pairingReady message)
        let result = outputURL.withUnsafeFileSystemRepresentation { outputPath in
            rp_pairing_host_run("0.0.0.0", // Address
                                0, // Port
                                "AltStore", // Name
                                "Mac16,11", // Model (2025 Mac mini)
                                outputPath,
                                ALTPairingReadyCallback,
                                ALTPairingPinCallback, // Doesn't do anything
                                context,
                                &output)
        }
        
        guard result == 0 else {
            guard let cErrorMessage = output.error else { throw PairError.unknown() }
            
            let errorMessage = String(cString: cErrorMessage)
            throw PairError.unknown(failureReason: errorMessage)
        }
        
        let data = try Data(contentsOf: outputURL)
        
        // Validate data is in correct format.
        _ = try FetchPairingFileOperation.PairingFile(data: data)
        
        return data
    }
}

@available(iOS 27, *)
private let ALTPairingReadyCallback: RpPairingHostReadyCb = { (context, cServiceID, port, keys, values, count) in
    guard let context, let cServiceID else { return }
    
    let serviceID = String(cString: cServiceID)
    let operation = Unmanaged<PairDeviceOperation>.fromOpaque(context).takeUnretainedValue()
    
    var txtRecord: [String: Data] = [:]
    if let keys, let values
    {
        for i in 0 ..< Int(count)
        {
            guard let cKey = keys[i], let cValue = values[i] else { continue }
            
            let key = String(cString: cKey)
            let value = String(cString: cValue)
            txtRecord[key] = Data(value.utf8)
        }
    }
    
    let message = PairingReadyMessage(serviceID: serviceID, port: Int(port), txtRecord: txtRecord)
    NotificationCenter.default.post(message, subject: operation)
}

@available(iOS 27, *)
private let ALTPairingPinCallback: RpPairingHostPinCb = { cPin, ctx in
    guard let cPin else { return }
    
    let pin = String(cString: cPin)
    Logger.main.info("Pairing device with PIN \(pin, privacy: .public)...")
}
