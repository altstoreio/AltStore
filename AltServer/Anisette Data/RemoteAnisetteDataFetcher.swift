//
//  RemoteAnisetteDataFetcher.swift
//  AltServer
//
//  Created by Nick Clyde on 9/16/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import Combine
import CryptoKit
import OSLog
import RegexBuilder

private extension URL
{
    static let appleGSALookup = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!
    static let anisetteServers = URL(string: "https://cdn.altstore.io/file/altstore/altstore/anisette-servers.json")!
}

struct AnisetteServer: Decodable
{
    var name: String
    var url: URL
}

// Plain value returned across the actor boundary; ALTAnisetteData itself isn't Sendable.
struct RemoteAnisetteData: Sendable
{
    var machineID: String
    var oneTimePassword: String
    var localUserID: String
    var routingInfo: UInt64
    var deviceUniqueIdentifier: String
    var deviceSerialNumber: String
    var deviceDescription: String

    func makeAnisetteData() -> ALTAnisetteData
    {
        return ALTAnisetteData(machineID: self.machineID,
                               oneTimePassword: self.oneTimePassword,
                               localUserID: self.localUserID,
                               routingInfo: self.routingInfo,
                               deviceUniqueIdentifier: self.deviceUniqueIdentifier,
                               deviceSerialNumber: self.deviceSerialNumber,
                               deviceDescription: self.deviceDescription,
                               date: Date(),
                               locale: .current,
                               timeZone: .current)
    }
}

// Stable identity for the remote anisette "device": 16 random bytes, plus the adi.pb
// provisioning blob issued for that identity. Both are persisted so Apple sees the same
// machine across launches (otherwise every install would trigger a fresh 2FA prompt).
private struct AnisetteIdentity: Codable
{
    var bytes: Data
    var adiPB: Data?
    var serverURL: URL?

    var identifier: String { self.bytes.base64EncodedString() }
    var localUserID: String { SHA256.hash(data: self.bytes).map { String(format: "%02X", $0) }.joined() }
    var deviceID: String { self.bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }.uuidString }

    static func make() -> AnisetteIdentity
    {
        let bytes = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        return AnisetteIdentity(bytes: bytes)
    }
}

private struct AnisetteIdentityStore
{
    let fileURL = FileManager.default.altserverDirectory.appendingPathComponent("AnisetteIdentity.json")

    func load() -> AnisetteIdentity?
    {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return nil }

        do
        {
            let data = try Data(contentsOf: self.fileURL)
            let identity = try JSONDecoder().decode(AnisetteIdentity.self, from: data)
            return identity
        }
        catch
        {
            Logger.main.error("Ignoring unreadable anisette identity at \(self.fileURL.path, privacy: .public). \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ identity: AnisetteIdentity) throws
    {
        try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(identity)
        try data.write(to: self.fileURL, options: .atomic)

        // adi.pb is effectively a device credential, so keep it owner-readable only.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.fileURL.path)
    }
}

// Fetches anisette data from a remote anisette server using the v3 protocol.
//
// macOS 26 and later gate AOSKit's anisette generation behind private entitlements, so AltServer
// can no longer produce a machine ID itself. This is the same fallback AltStore uses on-device
// (see AltStore/Operations/FetchAnisetteDataOperation.swift) and mirrors SideStore's client.
@available(macOS 13, *)
actor RemoteAnisetteDataFetcher
{
    static let shared = RemoteAnisetteDataFetcher()

    private static let timeout: TimeInterval = 90
    private static let placeholderSerialNumber = "C02LKHBBFD57"

    private let session: URLSession
    private let store = AnisetteIdentityStore()

    // Concurrent requests (e.g. several AltStore refreshes at once) share one in-flight fetch,
    // which also prevents two provisioning sessions from racing to write the identity file.
    private var currentTask: Task<RemoteAnisetteData, Error>?

    private init()
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30

        self.session = URLSession(configuration: configuration)
    }

    func fetchAnisetteData() async throws -> RemoteAnisetteData
    {
        if let currentTask
        {
            return try await currentTask.value
        }

        let task = Task {
            try await self.withTimeout(RemoteAnisetteDataFetcher.timeout) {
                try await self.fetchAnisetteDataFromAvailableServer()
            }
        }

        self.currentTask = task
        defer { self.currentTask = nil }

        return try await task.value
    }
}

@available(macOS 13, *)
private extension RemoteAnisetteDataFetcher
{
    func fetchAnisetteDataFromAvailableServer() async throws -> RemoteAnisetteData
    {
        // Explicit override: `defaults write com.rileytestut.AltServer AnisetteServerURL https://…`
        if let serverURL = UserDefaults.standard.anisetteServerURL
        {
            Logger.main.notice("Using configured anisette server \(serverURL.absoluteString, privacy: .public).")
            return try await self.fetchAnisetteData(from: serverURL)
        }

        var candidateURLs: [URL] = []

        // Prefer the server that worked last time so we keep reusing the same provisioned identity.
        if let preferredURL = UserDefaults.standard.preferredAnisetteServerURL
        {
            candidateURLs.append(preferredURL)
        }

        do
        {
            let servers = try await self.fetchServers()
            candidateURLs += servers.map(\.url).shuffled().filter { !candidateURLs.contains($0) }
        }
        catch
        {
            Logger.main.error("Failed to fetch anisette server list. \(error.localizedDescription, privacy: .public)")
        }

        guard !candidateURLs.isEmpty else { throw AnisetteError.remoteServerUnavailable() }

        var lastError: Error?

        for serverURL in candidateURLs
        {
            do
            {
                let anisetteData = try await self.fetchAnisetteData(from: serverURL)
                UserDefaults.standard.preferredAnisetteServerURL = serverURL
                return anisetteData
            }
            catch
            {
                Logger.main.error("Anisette server \(serverURL.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public). Trying next.")
                lastError = error
            }
        }

        throw lastError ?? AnisetteError.remoteServerUnavailable()
    }

    func fetchServers() async throws -> [AnisetteServer]
    {
        struct Response: Decodable
        {
            var servers: [AnisetteServer]
        }

        let response: Response = try await self.send(URLRequest(url: .anisetteServers), decoder: JSONDecoder(), anisetteServerURL: nil)
        return response.servers
    }

    func fetchAnisetteData(from serverURL: URL) async throws -> RemoteAnisetteData
    {
        // 1. Fetch client_info from the server.
        let (clientInfo, userAgent) = try await self.fetchClientInfo(from: serverURL)

        // 2. Load or generate the persisted identity.
        var identity = self.store.load() ?? .make()

        // 3. Provision against this server if we don't have an adi.pb from it.
        if identity.adiPB == nil || identity.serverURL != serverURL
        {
            Logger.main.notice("No cached adi.pb for \(serverURL.absoluteString, privacy: .public); running anisette provisioning.")

            identity.adiPB = try await self.provision(against: serverURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
            identity.serverURL = serverURL
            try self.store.save(identity)
        }

        // 4. Fetch anisette headers, re-provisioning once if the server rejects our adi.pb.
        var headers = try await self.fetchHeaders(from: serverURL, identity: identity)

        if case .rejected(let message) = headers
        {
            Logger.main.error("Anisette server rejected cached adi.pb (\(message ?? "no message", privacy: .public)); re-provisioning.")

            identity.adiPB = try await self.provision(against: serverURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
            identity.serverURL = serverURL
            try self.store.save(identity)

            headers = try await self.fetchHeaders(from: serverURL, identity: identity)
        }

        guard case .headers(let machineID, let oneTimePassword, let routingInfo) = headers else {
            throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL)
        }

        // 5. Assemble the result. Apple rejects sign-ins that identify as Xcode, so report akd instead.
        let anisetteData = RemoteAnisetteData(machineID: machineID,
                                              oneTimePassword: oneTimePassword,
                                              localUserID: identity.localUserID,
                                              routingInfo: routingInfo,
                                              deviceUniqueIdentifier: identity.deviceID,
                                              deviceSerialNumber: RemoteAnisetteDataFetcher.placeholderSerialNumber,
                                              deviceDescription: self.sanitizedDeviceDescription(clientInfo))
        return anisetteData
    }

    func fetchClientInfo(from serverURL: URL) async throws -> (clientInfo: String, userAgent: String)
    {
        struct Response: Decodable
        {
            var clientInfo: String
            var userAgent: String
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let clientInfoURL = serverURL.appending(components: "v3", "client_info")
        let response: Response = try await self.send(URLRequest(url: clientInfoURL), decoder: decoder, anisetteServerURL: serverURL)

        return (response.clientInfo, response.userAgent)
    }

    enum HeadersResult
    {
        case headers(machineID: String, oneTimePassword: String, routingInfo: UInt64)
        case rejected(message: String?)
    }

    func fetchHeaders(from serverURL: URL, identity: AnisetteIdentity) async throws -> HeadersResult
    {
        guard let adiPB = identity.adiPB else { throw AnisetteError.provisioningFailed(debugDescription: "Missing adi.pb.") }

        struct Body: Encodable
        {
            var identifier: String
            var adi_pb: String
        }

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

        var request = URLRequest(url: serverURL.appending(components: "v3", "get_headers"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(identifier: identity.identifier, adi_pb: String(decoding: adiPB, as: UTF8.self)))

        let response: Response = try await self.send(request, decoder: JSONDecoder(), anisetteServerURL: serverURL)

        guard response.result != "GetHeadersError" else {
            return .rejected(message: response.message)
        }

        guard let machineID = response.machineID,
              let oneTimePassword = response.oneTimePassword,
              let routingInfoString = response.routingInfo,
              let routingInfo = UInt64(routingInfoString)
        else {
            Logger.main.error("Anisette headers response was missing required fields.")
            throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL)
        }

        return .headers(machineID: machineID, oneTimePassword: oneTimePassword, routingInfo: routingInfo)
    }

    // Drives the v3 provisioning handshake: the server tells us what to ask Apple for, we relay
    // Apple's answers back over the socket, and the server returns the resulting adi.pb.
    func provision(against serverURL: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) async throws -> Data
    {
        let jsonEncoder = JSONEncoder()
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml

        // 1. Look up Apple's start/end provisioning URLs.
        struct LookupResponse: Decodable
        {
            var urls: URLs

            struct URLs: Decodable
            {
                var midStartProvisioning: String
                var midFinishProvisioning: String
            }
        }

        let lookupRequest = self.makeAppleRequest(for: .appleGSALookup, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
        let lookupResponse: LookupResponse = try await self.send(lookupRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)

        guard let startProvisioningURL = URL(string: lookupResponse.urls.midStartProvisioning),
              let endProvisioningURL = URL(string: lookupResponse.urls.midFinishProvisioning)
        else {
            throw AnisetteError.provisioningFailed(debugDescription: "Couldn’t construct Apple GSA provisioning URLs.")
        }

        // 2. Open a WebSocket session with the anisette server.
        var socketRequest = URLRequest(url: serverURL.appending(components: "v3", "provisioning_session"))
        socketRequest.timeoutInterval = 30

        let socket = self.session.webSocketTask(with: socketRequest)
        socket.resume()

        defer { socket.cancel(with: .normalClosure, reason: nil) }

        struct Message: Decodable
        {
            var result: String
            var message: String?
            var cpim: String?
            var adi_pb: String?
        }

        func sendJSON<T: Encodable>(_ value: T) async throws
        {
            let data = try jsonEncoder.encode(value)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        }

        // 3. Respond to each server prompt until ProvisioningSuccess.
        while true
        {
            let socketMessage = try await socket.receive()

            guard case .string(let text) = socketMessage else {
                Logger.main.error("Received unexpected non-string message from anisette server.")
                throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL)
            }

            let message: Message
            do
            {
                message = try JSONDecoder().decode(Message.self, from: Data(text.utf8))
            }
            catch
            {
                throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL, underlyingError: error)
            }

            Logger.main.debug("Received provisioning response: \(message.result, privacy: .public)")

            switch message.result
            {
            case "GiveIdentifier":
                struct IdentifierMessage: Encodable
                {
                    var identifier: String
                }

                try await sendJSON(IdentifierMessage(identifier: identity.identifier))

            case "GiveStartProvisioningData":
                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: [String: String] = [:]
                }

                struct StartMessage: Codable
                {
                    var spim: String
                }

                struct Response: Decodable
                {
                    var Response: StartMessage
                }

                var startRequest = self.makeAppleRequest(for: startProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                startRequest.httpMethod = "POST"
                startRequest.httpBody = try plistEncoder.encode(Body())

                let startResponse: Response = try await self.send(startRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)
                try await sendJSON(StartMessage(spim: startResponse.Response.spim))

            case "GiveEndProvisioningData":
                guard let cpim = message.cpim else {
                    Logger.main.error("GiveEndProvisioningData message didn't include cpim.")
                    throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL)
                }

                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: Request

                    struct Request: Encodable
                    {
                        var cpim: String
                    }
                }

                struct EndMessage: Codable
                {
                    var ptm: String
                    var tk: String
                }

                struct Response: Decodable
                {
                    var Response: EndMessage
                }

                var endRequest = self.makeAppleRequest(for: endProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                endRequest.httpMethod = "POST"
                endRequest.httpBody = try plistEncoder.encode(Body(Request: .init(cpim: cpim)))

                let endResponse: Response = try await self.send(endRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)
                try await sendJSON(EndMessage(ptm: endResponse.Response.ptm, tk: endResponse.Response.tk))

            case "ProvisioningSuccess":
                guard let adiPB = message.adi_pb else {
                    Logger.main.error("ProvisioningSuccess message didn't include adi_pb.")
                    throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL)
                }

                Logger.main.notice("Anisette provisioning succeeded.")
                return Data(adiPB.utf8)

            default:
                // Unknown results are fatal: we don't know whether it's safe to keep going.
                Logger.main.error("Anisette server returned unrecognized result \(message.result, privacy: .public): \(message.message ?? "", privacy: .public)")
                throw AnisetteError.remoteServerInvalidResponse(serverURL: serverURL, debugDescription: message.message ?? message.result)
            }
        }
    }
}

@available(macOS 13, *)
private extension RemoteAnisetteDataFetcher
{
    func send<T: Decodable, Decoder: TopLevelDecoder>(_ request: URLRequest, decoder: Decoder, anisetteServerURL: URL?) async throws -> T where Decoder.Input == Data
    {
        let data: Data
        let urlResponse: URLResponse

        do
        {
            (data, urlResponse) = try await self.session.data(for: request)
        }
        catch let error as URLError where anisetteServerURL != nil
        {
            throw AnisetteError.remoteServerUnavailable(serverURL: anisetteServerURL, underlyingError: error)
        }

        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode != 200
        {
            Logger.main.error("Request to \(request.url?.absoluteString ?? "?", privacy: .public) failed with status \(httpResponse.statusCode).")

            let debugDescription = "The server returned HTTP error code \(httpResponse.statusCode)."

            if let anisetteServerURL
            {
                throw AnisetteError.remoteServerUnavailable(serverURL: anisetteServerURL, debugDescription: debugDescription)
            }

            throw AnisetteError.provisioningFailed(debugDescription: debugDescription)
        }

        do
        {
            return try decoder.decode(T.self, from: data)
        }
        catch
        {
            if let anisetteServerURL
            {
                throw AnisetteError.remoteServerInvalidResponse(serverURL: anisetteServerURL, underlyingError: error)
            }

            throw AnisetteError.provisioningFailed(underlyingError: error)
        }
    }

    func makeAppleRequest(for url: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) -> URLRequest
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
        request.setValue(ISO8601DateFormatter().string(from: Date()), forHTTPHeaderField: "X-Apple-I-Client-Time")
        return request
    }

    func sanitizedDeviceDescription(_ clientInfo: String) -> String
    {
        let regex = Regex {
            "com.apple.dt.Xcode/"
            OneOrMore {
                ChoiceOf {
                    .digit
                    "."
                }
            }
        }
        .ignoresCase()

        return clientInfo.replacing(regex, with: "com.apple.akd/1.0")
    }

    func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AnisetteError.remoteServerUnavailable(debugDescription: "Timed out after \(Int(seconds)) seconds.")
            }

            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
