import Foundation
import Network
import XCTest
import dnssd

@testable import AltStore

final class LocalServiceDiscoveryTests: XCTestCase
{
    @MainActor
    func testDiscoversUsableNondefaultServerPort() async throws
    {
        let server = try LoopbackServer()
        defer { server.stop() }
        let firstPort = try await server.start()

        // Keep the first listener bound while replacing the one excluded port.
        let replacement = firstPort == 49152 ? try LoopbackServer() : nil
        defer { replacement?.stop() }
        let serverPort: UInt16
        if let replacement
        {
            serverPort = try await replacement.start()
        }
        else
        {
            serverPort = firstPort
        }
        XCTAssertNotEqual(serverPort, 49152)

        let serviceType = Self.uniqueServiceType()
        let registration = try ServiceRegistration(serviceType: serviceType, port: serverPort)
        defer { registration.stop() }
        try await registration.waitUntilRegistered()

        let port = await Self.discover(serviceType)
        let discoveredPort = try XCTUnwrap(port)
        XCTAssertEqual(discoveredPort, serverPort)

        let endpointPort = try XCTUnwrap(NWEndpoint.Port(rawValue: discoveredPort))
        let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        defer { connection.cancel() }
        let exchanged = XCTestExpectation(description: "Exchange bytes with discovered server")
        connection.start(queue: .main)
        connection.send(content: Data([0x37]), completion: .contentProcessed { error in
            XCTAssertNil(error)
            if error != nil
            {
                exchanged.fulfill()
            }
            else
            {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(data, Data([0x38]))
                    exchanged.fulfill()
                }
            }
        })
        let result = await XCTWaiter.fulfillment(of: [exchanged], timeout: 5)
        XCTAssertEqual(result, .completed)
    }

    @MainActor
    func testRediscoversChangedAdvertisedPort() async throws
    {
        let serviceType = Self.uniqueServiceType()
        let original = try ServiceRegistration(serviceType: serviceType, port: 49621)
        defer { original.stop() }
        try await original.waitUntilRegistered()
        let firstPort = await Self.discover(serviceType)
        XCTAssertEqual(firstPort, 49621)
        original.stop()

        let replacement = try ServiceRegistration(serviceType: serviceType, port: 49622)
        defer { replacement.stop() }
        try await replacement.waitUntilRegistered()
        let secondPort = await Self.discover(serviceType)
        XCTAssertEqual(secondPort, 49622)
    }

    @MainActor
    func testCancellationBeforeDiscoveryReturnsNil() async throws
    {
        let serviceType = Self.uniqueServiceType()
        let registration = try ServiceRegistration(serviceType: serviceType, port: 49621)
        defer { registration.stop() }
        try await registration.waitUntilRegistered()

        let completed = XCTestExpectation(description: "Already-cancelled discovery completes")
        var port: UInt16?
        let task = Task { @MainActor in
            port = await LocalServiceDiscovery.port(for: serviceType)
            completed.fulfill()
        }
        // This actor does not yield between creating and cancelling the task.
        task.cancel()
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(result, .completed)
        XCTAssertNil(port)
    }

    @MainActor
    func testCancellationDuringDiscoveryReturnsPromptly() async throws
    {
        let serviceType = Self.uniqueServiceType()
        let started = XCTestExpectation(description: "Discovery task starts")
        let completed = XCTestExpectation(description: "Cancelled discovery completes")
        var port: UInt16?
        let task = Task { @MainActor in
            started.fulfill()
            port = await LocalServiceDiscovery.port(for: serviceType)
            completed.fulfill()
        }
        defer { task.cancel() }
        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(startResult, .completed)
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(result, .completed)
        XCTAssertNil(port)
    }

    @MainActor
    func testMissingServiceReturnsNilWithinDeadline() async
    {
        let port = await Self.discover(Self.uniqueServiceType())
        XCTAssertNil(port)
    }

    private static func uniqueServiceType() -> String
    {
        // The service label, including its leading underscore, is 15 characters.
        return "_as" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12) + "._tcp"
    }

    @MainActor
    private static func discover(_ serviceType: String) async -> UInt16?
    {
        let completed = XCTestExpectation(description: "Discovery completes within its deadline")
        var port: UInt16?
        let task = Task { @MainActor in
            port = await LocalServiceDiscovery.port(for: serviceType)
            completed.fulfill()
        }
        defer { task.cancel() }
        // Leave scheduling margin around the production three-second deadline.
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(result, .completed)
        return port
    }
}

@MainActor
private final class ServiceRegistration
{
    private var reference: DNSServiceRef?
    private let registered = XCTestExpectation(description: "Local-only service registration completes")
    private var registrationError = DNSServiceErrorType(kDNSServiceErr_NoError)
    private var receivedReply = false

    init(serviceType: String, port: UInt16) throws
    {
        let error = DNSServiceRegister(&self.reference, 0, kDNSServiceInterfaceIndexLocalOnly,
                                       "AltStore Discovery Test", serviceType, "local.", nil,
                                       port.bigEndian, 0, nil, { _, _, error, _, _, _, context in
            guard let context else { return }
            let registration = Unmanaged<ServiceRegistration>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard !registration.receivedReply else { return }
                registration.receivedReply = true
                registration.registrationError = error
                registration.registered.fulfill()
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        guard error == kDNSServiceErr_NoError, let reference = self.reference else
        {
            self.stop()
            throw NSError(domain: "DNSServiceError", code: Int(error))
        }
        let queueError = DNSServiceSetDispatchQueue(reference, .main)
        guard queueError == kDNSServiceErr_NoError else
        {
            self.stop()
            throw NSError(domain: "DNSServiceError", code: Int(queueError))
        }
    }

    func waitUntilRegistered() async throws
    {
        let result = await XCTWaiter.fulfillment(of: [self.registered], timeout: 5)
        XCTAssertEqual(result, .completed)
        guard result == .completed else
        {
            throw NSError(domain: "LocalServiceDiscoveryTests", code: 1)
        }
        guard self.registrationError == kDNSServiceErr_NoError else
        {
            throw NSError(domain: "DNSServiceError", code: Int(self.registrationError))
        }
    }

    func stop()
    {
        if let reference = self.reference
        {
            DNSServiceRefDeallocate(reference)
            self.reference = nil
        }
    }
}

@MainActor
private final class LoopbackServer
{
    private let listener: NWListener
    private var connections = [NWConnection]()

    init() throws
    {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16
    {
        let ready = XCTestExpectation(description: "Loopback listener starts")
        var startupError: NWError?
        var receivedState = false
        self.listener.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                guard !receivedState else { return }
                switch state
                {
                case .ready:
                    receivedState = true
                    ready.fulfill()
                case .failed(let error):
                    receivedState = true
                    startupError = error
                    ready.fulfill()
                default:
                    break
                }
            }
        }
        self.listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else
                {
                    connection.cancel()
                    return
                }
                self.connections.append(connection)
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(data, Data([0x37]))
                    connection.send(content: Data([0x38]), completion: .contentProcessed { error in
                        XCTAssertNil(error)
                    })
                }
            }
        }
        self.listener.start(queue: .main)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(result, .completed)
        if let startupError
        {
            throw startupError
        }
        return try XCTUnwrap(self.listener.port?.rawValue)
    }

    func stop()
    {
        self.listener.cancel()
        self.connections.forEach { $0.cancel() }
        self.connections.removeAll()
    }
}
