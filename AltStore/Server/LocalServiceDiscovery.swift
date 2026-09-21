//
//  LocalServiceDiscovery.swift
//  AltStore
//

import Foundation
import dnssd

@MainActor
final class LocalServiceDiscovery
{
    private struct Service: Equatable
    {
        var name: String
        var type: String
        var domain: String
        var interfaceIndex: UInt32
    }

    private let deadline = DispatchTime.now() + .seconds(3)
    private var continuation: CheckedContinuation<UInt16?, Never>?
    private var timeout: DispatchWorkItem?
    private var browseReference: DNSServiceRef?
    private var resolveReference: DNSServiceRef?
    private var services = [Service]()
    private var selectedService: Service?
    private var resolvedPort: UInt16?
    private var hasPendingBrowseResults = false
    private var isFinished = false

    static func port(for serviceType: String) async -> UInt16?
    {
        let discovery = LocalServiceDiscovery()
        // DNS-SD does not retain its context. Keep the instance alive until finish()
        // has deallocated every reference and resumed the continuation.
        defer { withExtendedLifetime(discovery) {} }

        let port = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                discovery.start(serviceType: serviceType, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                discovery.finish(port: nil)
            }
        }

        // Cancellation can race with a successful callback already queued on main.
        return Task.isCancelled ? nil : port
    }

    private func start(serviceType: String, continuation: CheckedContinuation<UInt16?, Never>)
    {
        // A cancellation handler may finish before the continuation is installed.
        guard !self.isFinished, !Task.isCancelled else
        {
            continuation.resume(returning: nil)
            return
        }

        self.continuation = continuation

        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.finish(port: nil)
            }
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: self.deadline, execute: timeout)

        var reference: DNSServiceRef?
        // LocalOnly finds all services registered on this device, including those
        // advertised on physical interfaces, without accepting another LAN device.
        let error = DNSServiceBrowse(&reference, 0, kDNSServiceInterfaceIndexLocalOnly, serviceType, "local.", { _, flags, interfaceIndex, error, name, type, domain, context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let discovery = Unmanaged<LocalServiceDiscovery>.fromOpaque(context).takeUnretainedValue()
                discovery.didBrowse(flags: flags, interfaceIndex: interfaceIndex, error: error, name: name, type: type, domain: domain)
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        guard error == kDNSServiceErr_NoError, let reference else
        {
            self.finish(port: nil)
            return
        }

        self.browseReference = reference
        guard DNSServiceSetDispatchQueue(reference, DispatchQueue.main) == kDNSServiceErr_NoError else
        {
            self.finish(port: nil)
            return
        }
    }

    private func didBrowse(flags: DNSServiceFlags, interfaceIndex: UInt32, error: DNSServiceErrorType, name: UnsafePointer<CChar>?, type: UnsafePointer<CChar>?, domain: UnsafePointer<CChar>?)
    {
        guard !self.isFinished else { return }
        // Other callback parameters are undefined on error.
        guard error == kDNSServiceErr_NoError, DispatchTime.now() < self.deadline,
              let name, let type, let domain else
        {
            self.finish(port: nil)
            return
        }

        let service = Service(name: String(cString: name), type: String(cString: type), domain: String(cString: domain), interfaceIndex: interfaceIndex)
        self.hasPendingBrowseResults = flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) != 0

        if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0
        {
            if !self.services.contains(service)
            {
                self.services.append(service)
            }
        }
        else
        {
            self.services.removeAll { $0 == service }
            if self.selectedService == service
            {
                if let reference = self.resolveReference
                {
                    DNSServiceRefDeallocate(reference)
                    self.resolveReference = nil
                }
                self.selectedService = nil
                self.resolvedPort = nil
            }
        }

        // Drain each browse batch before choosing or accepting a result, so a
        // removal in that batch cannot leave us using its stale server port.
        guard !self.hasPendingBrowseResults else { return }
        if let port = self.resolvedPort
        {
            self.finish(port: port)
        }
        else if self.resolveReference == nil, let service = self.services.first
        {
            self.resolve(service)
        }
    }

    private func resolve(_ service: Service)
    {
        self.selectedService = service

        var reference: DNSServiceRef?
        // Retain the local-only scope even if Browse reported a physical interface.
        let error = DNSServiceResolve(&reference, 0, kDNSServiceInterfaceIndexLocalOnly, service.name, service.type, service.domain, { reference, _, _, error, _, _, port, _, _, context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let discovery = Unmanaged<LocalServiceDiscovery>.fromOpaque(context).takeUnretainedValue()
                discovery.didResolve(reference: reference, error: error, port: port)
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        guard error == kDNSServiceErr_NoError, let reference else
        {
            self.finish(port: nil)
            return
        }

        self.resolveReference = reference
        guard DNSServiceSetDispatchQueue(reference, DispatchQueue.main) == kDNSServiceErr_NoError else
        {
            self.finish(port: nil)
            return
        }
    }

    private func didResolve(reference: DNSServiceRef?, error: DNSServiceErrorType, port: UInt16)
    {
        guard !self.isFinished else { return }
        guard error == kDNSServiceErr_NoError, DispatchTime.now() < self.deadline else
        {
            self.finish(port: nil)
            return
        }
        guard reference == self.resolveReference, self.selectedService != nil else { return }

        let port = UInt16(bigEndian: port)
        guard port != 0 else
        {
            self.finish(port: nil)
            return
        }

        self.resolvedPort = port
        if !self.hasPendingBrowseResults
        {
            self.finish(port: port)
        }
    }

    private func finish(port: UInt16?)
    {
        guard !self.isFinished else { return }
        self.isFinished = true

        self.timeout?.cancel()
        self.timeout = nil

        // All callbacks and cleanup run on the same serial queue. Deallocation
        // terminates callbacks before the async caller can release their context.
        if let reference = self.resolveReference
        {
            DNSServiceRefDeallocate(reference)
            self.resolveReference = nil
        }
        if let reference = self.browseReference
        {
            DNSServiceRefDeallocate(reference)
            self.browseReference = nil
        }

        self.services.removeAll()
        self.selectedService = nil
        self.resolvedPort = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: port)
    }
}
