//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit
import Combine

import AltStoreCore
import AltSign
import Roxas

private extension URL
{
    static let appleGSALookup = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!
}

extension FetchAnisetteDataOperation
{
    fileprivate struct AnisetteIdentity
    {
        let bytes: Data // 16 random bytes; stored as anisetteIdentityKey in keychain

        var identifier: String { bytes.base64EncodedString() }
        var localUserID: String { SHA256.hash(data: bytes).map { String(format: "%02X", $0) }.joined() }
        var deviceID: String { bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }.uuidString }
        
        static func make() -> AnisetteIdentity
        {
            let new = AnisetteIdentity(bytes: Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }))
            return new
        }

        init(bytes: Data)
        {
            self.bytes = bytes
        }
    }
}

@objc(FetchAnisetteDataOperation)
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, @unchecked Sendable
{
    let context: OperationContext
    
    private let session: URLSession
    
    init(context: OperationContext)
    {
        self.context = context
        
        let configuration = URLSessionConfiguration.default
        
        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        
        self.session = URLSession(configuration: configuration)
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
                Logger.sideload.notice("Fetching anisette data...")

                let anisetteData: ALTAnisetteData

                // Use Remote AltServer when set up and preferred.
                if UserDefaults.shared.prefersRemoteAltServer
                {
                    // AltServerless route
                    anisetteData = try await self.fetchAnisetteDataFromAvailableServer()
                }
                else if let server = self.context.server
                {
                    anisetteData = try await self.fetchAnisetteData(fromAltServer: server)
                }
                else
                {
                    throw OperationError.serverNotFound
                }

                self.finish(.success(anisetteData))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}

private extension FetchAnisetteDataOperation
{
    func fetchAnisetteData(fromAltServer server: Server) async throws -> ALTAnisetteData
    {
        return try await withCheckedThrowingContinuation { continuation in
            // Existing bug causes completion to be called twice, so add a guard to prevent continuation assertion
            func finish(_ result: Result<ALTAnisetteData, Error>)
            {
                guard !self.isFinished else { return }
                continuation.resume(with: result)
            }
            
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let connection):
                    Logger.sideload.debug("Sending anisette data request...")

                    let request = AnisetteDataRequest()
                    connection.send(request) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            Logger.sideload.error("Failed to send anisette data request. \(error.localizedDescription, privacy: .public)")
                            finish(.failure(error))

                        case .success:
                            Logger.sideload.debug("Waiting for anisette data...")
                            connection.receiveResponse() { (result) in
                                switch result
                                {
                                case .failure(let error):
                                    Logger.sideload.error("Failed to receive anisette data response. \(error.localizedDescription, privacy: .public)")
                                    finish(.failure(error))

                                case .success(.error(let response)):
                                    Logger.sideload.error("Failed to receive anisette data. \(response.error.localizedDescription, privacy: .public)")
                                    finish(.failure(response.error))

                                case .success(.anisetteData(let response)):
                                    Logger.sideload.notice("Successfully received anisette data!")
                                    finish(.success(response.anisetteData))

                                case .success: finish(.failure(ALTServerError(.unknownResponse)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func fetchAnisetteDataFromAvailableServer() async throws -> ALTAnisetteData
    {
        // Use preferred URL if it exists.
        if let preferredURL = UserDefaults.shared.preferredAnisetteServerURL
        {
            return try await self.fetchAnisetteData(from: preferredURL)
        }

        // No preferred URL — fetch the list of available servers.
        let servers: [AnisetteServer]
        do
        {
            servers = try await AnisetteServerManager.shared.fetchServers()
        }
        catch
        {
            Logger.sideload.error("Failed to fetch remote anisette server list: \(error.localizedDescription, privacy: .public)")
            throw OperationError.invalidAnisetteResponse()
        }

        // Shuffle and try each server. If successful, set preferred URL.
        for server in servers.shuffled()
        {
            do
            {
                let anisetteData = try await self.fetchAnisetteData(from: server.url)
                UserDefaults.shared.preferredAnisetteServerURL = server.url
                return anisetteData
            }
            catch
            {
                Logger.sideload.error("Anisette server \(server.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public). Trying next.")
            }
        }

        Logger.sideload.error("All remote anisette servers failed.")
        throw OperationError.invalidAnisetteResponse()
    }
    
    // Based on SideStore's FetchAnisetteDataOperation: https://github.com/SideStore/SideStore/blob/develop/AltStore/Operations/FetchAnisetteDataOperation.swift
    func fetchAnisetteData(from serverURL: URL) async throws -> ALTAnisetteData
    {
        // 1. Fetch client_info from the server
        let clientInfoURL = serverURL.appending(components: "v3", "client_info")
        
        struct Response: Decodable
        {
            var clientInfo: String
            var userAgent: String
        }
        
        let decoder = Foundation.JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let response: Response = try await self.send(URLRequest(url: clientInfoURL), decoder: decoder)

        // 2. Load or generate the persisted device identity (16 random bytes -> derives identifier, localUserID, deviceID)
        let identity: AnisetteIdentity
        if let id = Keychain.shared.anisetteIdentityKey
        {
            identity = AnisetteIdentity(bytes: id)
        }
        else
        {
            identity = AnisetteIdentity.make()
            Keychain.shared.anisetteIdentityKey = identity.bytes
        }

        // 3. Provision against this server if we don't have a cached adi.pb
        let adiPB: Data
        if let pb = Keychain.shared.anisetteADIPB
        {
            adiPB = pb
        }
        else
        {
            Logger.sideload.notice("No cached adi.pb; running anisette provisioning against \(serverURL.absoluteString, privacy: .public).")
            adiPB = try await self.provision(against: serverURL, clientInfo: response.clientInfo, userAgent: response.userAgent, identity: identity)
            Keychain.shared.anisetteADIPB = adiPB
        }
        
        // 4. Fetch anisette headers
        let (machineID, oneTimePassword, routingInfo) = try await self.fetchHeaders(from: serverURL, identity: identity, adiPB: adiPB)

        // 5. Construct & return ALTAnisetteData
        return ALTAnisetteData(
            machineID: machineID,
            oneTimePassword: oneTimePassword,
            localUserID: identity.localUserID,
            routingInfo: routingInfo,
            deviceUniqueIdentifier: identity.deviceID,
            deviceSerialNumber: "C02LKHBBFD57",
            deviceDescription: response.clientInfo,
            date: .now,
            locale: .current,
            timeZone: .current
        )
    }

    func fetchHeaders(from serverURL: URL, identity: AnisetteIdentity, adiPB: Data) async throws -> (machineID: String, oneTimePassword: String, routingInfo: UInt64)
    {
        let headersURL = serverURL.appending(components: "v3", "get_headers")

        var request = URLRequest(url: headersURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable
        {
            var identifier: String
            var adi_pb: String
        }

        let body = Body(identifier: identity.identifier, adi_pb: String(decoding: adiPB, as: UTF8.self))
        request.httpBody = try JSONEncoder().encode(body)

        struct Response: Decodable
        {
            var result: String?
            var message: String?
            var machineID: String?
            var oneTimePassword: String?
            var routingInfo: String?

            private enum CodingKeys: String, CodingKey
            {
                case result
                case message
                case machineID = "X-Apple-I-MD-M"
                case oneTimePassword = "X-Apple-I-MD"
                case routingInfo = "X-Apple-I-MD-RINFO"
            }
        }

        let response: Response = try await self.send(request, decoder: Foundation.JSONDecoder())

        guard response.result != "GetHeadersError" else
        {
            Logger.sideload.error("Anisette headers request returned error: \(response.message ?? "(no message)", privacy: .public)")
            throw OperationError.invalidAnisetteResponse()
        }

        guard let machineID = response.machineID,
              let oneTimePassword = response.oneTimePassword,
              let routingInfoString = response.routingInfo,
              let routingInfo = UInt64(routingInfoString)
        else
        {
            Logger.sideload.error("Anisette headers response was missing required fields.")
            throw OperationError.invalidAnisetteResponse()
        }

        return (machineID, oneTimePassword, routingInfo)
    }

    // Based on SideStore's FetchAnisetteDataOperation: https://github.com/SideStore/SideStore/blob/develop/AltStore/Operations/FetchAnisetteDataOperation.swift
    func provision(against serverURL: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) async throws -> Data
    {
        let jsonEncoder = JSONEncoder()
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml

        // 1. Build Apple GSA lookup request
        let lookupRequest = self.makeAnisetteRequest(for: .appleGSALookup, clientInfo: clientInfo, userAgent: userAgent, identity: identity)

        // 2. Look up Apple's start/end provisioning URLs
        struct Response: Decodable
        {
            var urls: URLs

            struct URLs: Decodable
            {
                var midStartProvisioning: String
                var midFinishProvisioning: String
            }
        }

        let lookupResponse: Response = try await self.send(lookupRequest, decoder: PropertyListDecoder())
        
        guard let startProvisioningURL = URL(string: lookupResponse.urls.midStartProvisioning),
              let endProvisioningURL = URL(string: lookupResponse.urls.midFinishProvisioning)
        else {
            Logger.sideload.error("Failed to construct provisioning URLs from server response.")
            throw OperationError.unknown(failureReason: "Couldn’t construct Apple GSA provisioning URL.")
        }
        
        // 3. Create and open WebSocket session to anisette server
        let provisioningSessionURL = serverURL.appending(components: "v3", "provisioning_session")

        var socketRequest = URLRequest(url: provisioningSessionURL)
        socketRequest.timeoutInterval = 30
        
        let socket = self.session.webSocketTask(with: socketRequest)
        socket.resume()
        
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        // 4. Drive provisioning state machine: respond to each server prompt until ProvisioningSuccess
        while true
        {
            let message = try await socket.receiveMessage()
            
            guard case .string(let text) = message, let data = text.data(using: .utf8) else {
                Logger.sideload.error("Received unexpected non-string message from anisette server.")
                throw OperationError.invalidAnisetteResponse()
            }

            struct Message: Decodable
            {
                var result: String
                var message: String?
                var cpim: String?
                var adi_pb: String?
            }

            let response: Message = try Foundation.JSONDecoder().decode(Message.self, from: data)

            Logger.sideload.debug("Received provisioning response: \(response.result, privacy: .public)")
            
            switch response.result
            {
            case "GiveIdentifier":
                struct IDMessage: Encodable
                {
                    var identifier: String
                }
                
                let message = IDMessage(identifier: identity.identifier)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "GiveStartProvisioningData":
                var startRequest = self.makeAnisetteRequest(for: startProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                startRequest.httpMethod = "POST"
                
                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: [String: String] = [:]
                }
                
                let body = Body()
                startRequest.httpBody = try plistEncoder.encode(body)

                struct StartMessage: Codable
                {
                    var spim: String
                }
                
                struct Response: Decodable
                {
                    var Response: StartMessage
                }

                let startResponse: Response = try await self.send(startRequest, decoder: PropertyListDecoder())

                let message = StartMessage(spim: startResponse.Response.spim)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "GiveEndProvisioningData":
                guard let cpim = response.cpim else {
                    Logger.sideload.error("GiveEndProvisioningData message didn't include cpim.")
                    throw OperationError.invalidAnisetteResponse()
                }
                
                var endRequest = self.makeAnisetteRequest(for: endProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                endRequest.httpMethod = "POST"
                
                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: Request
                    
                    struct Request: Encodable
                    {
                        var cpim: String
                    }
                }
                
                let body = Body(Request: .init(cpim: cpim))
                endRequest.httpBody = try plistEncoder.encode(body)

                struct EndMessage: Codable
                {
                    var ptm: String
                    var tk: String
                }
                
                struct Response: Decodable
                {
                    var Response: EndMessage
                }

                let endResponse: Response = try await self.send(endRequest, decoder: PropertyListDecoder())

                let message = EndMessage(ptm: endResponse.Response.ptm, tk: endResponse.Response.tk)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "ProvisioningSuccess":
                guard let adiPB = response.adi_pb, let adiPBData = adiPB.data(using: .utf8) else {
                    Logger.sideload.error("ProvisioningSuccess message didn't include adi_pb.")
                    throw OperationError.invalidAnisetteResponse()
                }
                                
                Logger.sideload.notice("Provisioning succeeded.")
                
                return adiPBData
                
            default:
                // Any unrecognized result is treated as fatal — we don't know what it means, so don't assume it's safe to ignore.
                Logger.sideload.error("Anisette server returned unrecognized result: \(response.result, privacy: .public) — \(response.message ?? "", privacy: .public)")
                throw OperationError.invalidAnisetteResponse()
            }
        }
    }
}

private extension FetchAnisetteDataOperation
{
    func send<T: Decodable, Decoder: TopLevelDecoder>(_ request: URLRequest, decoder: Decoder) async throws -> T where Decoder.Input == Data
    {
        let (data, urlResponse) = try await self.session.data(for: request)

        if let urlResponse = urlResponse as? HTTPURLResponse
        {
            guard urlResponse.statusCode == 200 else
            {
                Logger.sideload.error("Request to \(request.url?.absoluteString ?? "?", privacy: .public) failed with status \(urlResponse.statusCode).")
                
                if urlResponse.statusCode == 429 // TODO: create specific operation error case
                {
                    throw OperationError.unknown(failureReason: String(localized: "Too many requests. Please wait a moment and try again.", comment: nil))
                }
                
                throw OperationError.unknown(failureReason: String(localized: "The server returned HTTP error code \(urlResponse.statusCode).", comment: nil))
            }
        }

        return try decoder.decode(T.self, from: data)
    }
    
    func makeAnisetteRequest(for url: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) -> URLRequest
    {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(identity.localUserID, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(identity.deviceID, forHTTPHeaderField: "X-Mme-Device-Id")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation(), forHTTPHeaderField: "X-Apple-I-TimeZone")
        request.setValue(ISO8601DateFormatter().string(from: .now), forHTTPHeaderField: "X-Apple-I-Client-Time")
        return request
    }
}

private extension URLSessionWebSocketTask
{
    func receiveMessage() async throws -> URLSessionWebSocketTask.Message
    {
        try await withCheckedThrowingContinuation { continuation in
            self.receive { result in
                continuation.resume(with: result)
            }
        }
    }
}
