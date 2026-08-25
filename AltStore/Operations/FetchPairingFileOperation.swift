//
//  FetchPairingFileOperation.swift
//  AltStore
//
//  Created by Caroline Moore on 5/28/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

@objc(FetchPairingFileOperation)
class FetchPairingFileOperation: ResultOperation<Void>, @unchecked Sendable
{
    let context: OperationContext

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

        Task<Void, Never>
        {
            do
            {
                Logger.sideload.notice("Fetching pairing file from AltServer...")

                let pairingFile = try await self.fetchPairingFile()

                Keychain.shared.devicePairingFile = pairingFile.data
                UserDefaults.standard.prefersRemoteAltServer = true // Once pairing file is set, default to on-device path.

                Logger.sideload.notice("Configured pairing file from AltServer (\(pairingFile.data.count) bytes).")

                self.finish(.success(()))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}

private extension FetchPairingFileOperation
{
    func fetchPairingFile() async throws -> PairingFile
    {
        guard let server = self.context.server else { throw OperationError.serverNotFound }
        guard server.connectionType == .wired else { throw OperationError.wiredConnectionRequired() }
        guard let udid = UserDefaults.shared.deviceID else { throw OperationError.unknownUDID }

        return try await withCheckedThrowingContinuation { continuation in
            // Existing bug can call completion twice, so guard against the continuation assert.
            func finish(_ result: Result<PairingFile, Error>)
            {
                guard !self.isFinished else { return }
                continuation.resume(with: result)
            }

            ServerManager.shared.connect(to: server) { result in
                switch result
                {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let connection):
                    Logger.sideload.debug("Sending pairing file request...")

                    let request = PairingFileRequest(udid: udid)
                    connection.send(request) { result in
                        switch result
                        {
                        case .failure(let error):
                            Logger.sideload.error("Failed to send pairing file request. \(error.localizedDescription, privacy: .public)")
                            finish(.failure(error))

                        case .success:
                            Logger.sideload.debug("Waiting for pairing file...")
                            connection.receiveResponse { result in
                                switch result
                                {
                                case .failure(let error):
                                    Logger.sideload.error("Failed to receive pairing file response. \(error.localizedDescription, privacy: .public)")
                                    finish(.failure(error))

                                case .success(.error(let response)):
                                    Logger.sideload.error("AltServer failed to generate pairing file. \(response.error.localizedDescription, privacy: .public)")
                                    finish(.failure(response.error))

                                case .success(.pairingFile(let response)):
                                    // Log byte count only; bytes contain sensitive info (device identifier) we don't want to expose.
                                    Logger.sideload.notice("Received pairing file (\(response.pairingFile.count) bytes).")
                                    do { finish(.success(try PairingFile(data: response.pairingFile))) }
                                    catch { finish(.failure(error)) }

                                case .success: finish(.failure(ALTServerError(.unknownResponse)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension FetchPairingFileOperation
{
    // Device pairing file validated on init: must contain either UDID (lockdown) or private_key (RP-pairing).
    struct PairingFile
    {
        let data: Data

        init(data: Data) throws
        {
            struct Contents: Decodable
            {
                var UDID: String?
                var private_key: Data?
            }

            let contents: Contents
            do
            {
                contents = try PropertyListDecoder().decode(Contents.self, from: data)
            }
            catch
            {
                Logger.sideload.error("Failed to decode pairing file. \(error.localizedDescription, privacy: .public)")
                throw OperationError.invalidPairingFile()
            }

            guard contents.UDID != nil || contents.private_key != nil else
            {
                Logger.sideload.error("Invalid pairing file from AltServer: missing UDID/private_key.")
                throw OperationError.invalidPairingFile()
            }

            self.data = data
        }
    }

}
