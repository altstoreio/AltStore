//
//  AnisetteDataManager.swift
//  AltServer
//
//  Created by Riley Testut on 11/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import OSLog

private extension Bundle
{
    struct ID
    {
        static let mail = "com.apple.mail"
        static let altXPC = "com.rileytestut.AltXPC"
    }
}

private extension ALTAnisetteData
{
    func sanitize(byReplacingBundleID bundleID: String)
    {
        guard let range = self.deviceDescription.lowercased().range(of: "(" + bundleID.lowercased()) else { return }
        
        var adjustedDescription = self.deviceDescription[..<range.lowerBound]
        adjustedDescription += "(com.apple.dt.Xcode/3594.4.19)>"
        
        self.deviceDescription = String(adjustedDescription)
    }
}

extension ALTAnisetteData
{
    /// Anisette servers respond with the request headers Apple expects, so map them to their ALTAnisetteData counterparts.
    convenience init(anisetteServerResponse json: [String: Any]) throws
    {
        func value(forHeader header: String) throws -> String
        {
            // Implementations disagree on capitalization (X-MMe- vs X-Mme-), and HTTP headers
            // are case-insensitive anyway, so match them that way.
            let match = json.first { $0.key.caseInsensitiveCompare(header) == .orderedSame }
            
            switch match?.value
            {
            case let string as String: return string
            case let number as NSNumber: return number.stringValue // Not all servers encode routing info as a string.
            default: throw AnisetteError.invalidServerResponse(header)
            }
        }
        
        let machineID = try value(forHeader: "X-Apple-I-MD-M")
        let oneTimePassword = try value(forHeader: "X-Apple-I-MD")
        let localUserID = try value(forHeader: "X-Apple-I-MD-LU")
        let deviceUniqueIdentifier = try value(forHeader: "X-Mme-Device-Id")
        let deviceDescription = try value(forHeader: "X-MMe-Client-Info")
        
        let rawRoutingInfo = try value(forHeader: "X-Apple-I-MD-RINFO")
        guard let routingInfo = UInt64(rawRoutingInfo) else { throw AnisetteError.invalidServerResponse("X-Apple-I-MD-RINFO") }
        
        // Unlike the values above, these don't have to match the ones used to generate the one-time password,
        // so fall back to defaults for servers that don't return them.
        let serialNumber = (try? value(forHeader: "X-Apple-I-SRL-NO")) ?? "0"
        let date = (try? value(forHeader: "X-Apple-I-Client-Time")).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let locale = (try? value(forHeader: "X-Apple-Locale")).map { Locale(identifier: $0) } ?? .current
        let timeZone = (try? value(forHeader: "X-Apple-I-TimeZone")).flatMap { TimeZone(abbreviation: $0) ?? TimeZone(identifier: $0) } ?? .current
        
        self.init(machineID: machineID,
                  oneTimePassword: oneTimePassword,
                  localUserID: localUserID,
                  routingInfo: routingInfo,
                  deviceUniqueIdentifier: deviceUniqueIdentifier,
                  deviceSerialNumber: serialNumber,
                  deviceDescription: deviceDescription,
                  date: date,
                  locale: locale,
                  timeZone: timeZone)
    }
}

@objc private protocol AOSUtilitiesProtocol
{
    static var machineSerialNumber: String? { get }
    static var machineUDID: String? { get }
    
    static func retrieveOTPHeadersForDSID(_ dsid: String) -> [String: Any]?
    
    // Non-static versions used for respondsToSelector:
    var machineSerialNumber: String? { get }
    var machineUDID: String? { get }
    func retrieveOTPHeadersForDSID(_ dsid: String) -> [String: Any]?
}

class AnisetteDataManager: NSObject
{
    static let shared = AnisetteDataManager()
    
    private var anisetteDataCompletionHandlers: [String: (Result<ALTAnisetteData, Error>) -> Void] = [:]
    private var anisetteDataTimers: [String: Timer] = [:]
    
    private lazy var xpcConnection: NSXPCConnection = {
        let connection = NSXPCConnection(serviceName: Bundle.ID.altXPC)
        connection.remoteObjectInterface = NSXPCInterface(with: AltXPCProtocol.self)
        connection.resume()
        return connection
    }()
    
    private override init()
    {
        super.init()
        
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(AnisetteDataManager.handleAnisetteDataResponse(_:)), name: Notification.Name("com.rileytestut.AltServer.AnisetteDataResponse"), object: nil)
    }
    
    func requestAnisetteData(_ completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        if let serverURL = UserDefaults.standard.anisetteServerURL
        {
            // An anisette server was explicitly configured, so treat it as the source of truth
            // instead of silently falling back to (potentially different) local anisette data.
            self.requestAnisetteData(from: serverURL, completion: completion)
            return
        }
        
        self.requestAnisetteDataFromAOSKit { (result) in
            do
            {
                let anisetteData = try result.get()
                completion(.success(anisetteData))
            }
            catch let aosKitError
            {
                // As of macOS 26, adid won't generate one-time passwords for unentitled apps, so
                // run Apple's own ADI libraries in a Linux guest where they still work.
                guard #available(macOS 13.0, *) else {
                    return self.requestAnisetteDataFromLegacyServices(reportedError: aosKitError, completion: completion)
                }
                
                AnisetteVirtualMachine.shared.requestAnisetteData { (result) in
                    switch result
                    {
                    case .success(let anisetteData): completion(.success(anisetteData))
                    case .failure(let error):
                        Logger.main.error("Failed to fetch anisette data from virtual machine. \(error.localizedDescription, privacy: .public)")
                        
                        // The virtual machine is the supported path now, so its failure is what's worth reporting.
                        self.requestAnisetteDataFromLegacyServices(reportedError: error, completion: completion)
                    }
                }
            }
        }
    }
}

private extension AnisetteDataManager
{
    /// Both of these require SIP and/or AMFI to be disabled, and neither survives macOS 26.
    func requestAnisetteDataFromLegacyServices(reportedError: Error, completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        self.requestAnisetteDataFromXPCService { (result) in
            do
            {
                let anisetteData = try result.get()
                completion(.success(anisetteData))
            }
            catch CocoaError.xpcConnectionInterrupted
            {
                // SIP and/or AMFI are not disabled, so fall back to Mail plug-in as last resort.
                self.requestAnisetteDataFromPlugin { (result) in
                    do
                    {
                        let anisetteData = try result.get()
                        completion(.success(anisetteData))
                    }
                    catch
                    {
                        Logger.main.error("Failed to fetch anisette data via Mail plug-in. \(error.localizedDescription, privacy: .public)")
                        
                        // Return original error.
                        completion(.failure(reportedError))
                    }
                }
            }
            catch
            {
                Logger.main.error("Failed to fetch anisette data via XPC service. \(error.localizedDescription, privacy: .public)")
                
                // Return original error.
                completion(.failure(reportedError))
            }
        }
    }
}

private extension AnisetteDataManager
{
    func requestAnisetteDataFromAOSKit(completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        do
        {
            let aosKitURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/AOSKit.framework")
            
            guard let aosKit = Bundle(url: aosKitURL) else { throw AnisetteError.aosKitFailure() }
            try aosKit.loadAndReturnError()
            
            guard let AOSUtilitiesClass = NSClassFromString("AOSUtilities"),
                  AOSUtilitiesClass.responds(to: #selector(AOSUtilitiesProtocol.retrieveOTPHeadersForDSID(_:))),
                  AOSUtilitiesClass.responds(to: #selector(getter: AOSUtilitiesProtocol.machineSerialNumber)),
                  AOSUtilitiesClass.responds(to: #selector(getter: AOSUtilitiesProtocol.machineUDID))
            else { throw AnisetteError.aosKitFailure() }
            
            let AOSUtilities = unsafeBitCast(AOSUtilitiesClass, to: AOSUtilitiesProtocol.Type.self)
            
            // -2 = Production environment (via https://github.com/ionescu007/Blackwood-4NT)
            guard let requestHeaders = AOSUtilities.retrieveOTPHeadersForDSID("-2") else { throw AnisetteError.missingValue("oneTimePassword") }
            
            // As of macOS 27, adid refuses to generate one-time passwords for apps without private entitlements,
            // and AOSKit reports the failure by returning an empty dictionary rather than nil.
            guard !requestHeaders.isEmpty else { throw AnisetteError.unsupportedOperatingSystem() }
            
            guard let machineID = requestHeaders["X-Apple-MD-M"] as? String else { throw AnisetteError.missingValue("machineID") }
            guard let oneTimePassword = requestHeaders["X-Apple-MD"] as? String else { throw AnisetteError.missingValue("oneTimePassword") }
            
            guard let deviceID = AOSUtilities.machineUDID else { throw AnisetteError.missingValue("deviceUniqueIdentifier") }
            guard let localUserID = deviceID.data(using: .utf8)?.base64EncodedString() else { throw AnisetteError.missingValue("localUserID") }
            
            let serialNumber = AOSUtilities.machineSerialNumber ?? "C02LKHBBFD57" // serialNumber can be nil, so provide valid fallback serial number.
            let routingInfo: UInt64 = 84215040 // Other known values: 17106176, 50660608
            
            let osVersion: OperatingSystemVersion
            let buildVersion: String
            
            if let build = ProcessInfo.processInfo.operatingSystemBuildVersion
            {
                osVersion = ProcessInfo.processInfo.operatingSystemVersion
                buildVersion = build
            }
            else
            {
                // Unknown build, so fall back to known valid macOS version.
                osVersion = OperatingSystemVersion(majorVersion: 13, minorVersion: 4, patchVersion: 0)
                buildVersion = "22F66"
            }
            
            let deviceModel = ProcessInfo.processInfo.deviceModel ?? "iMac21,1"
            let osName = (osVersion.majorVersion < 11) ? "Mac OS X" : "macOS"
            
            let serverFriendlyDescription = "<\(deviceModel)> <\(osName);\(osVersion.stringValue);\(buildVersion)> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
            
            let anisetteData = ALTAnisetteData(machineID: machineID,
                                               oneTimePassword: oneTimePassword,
                                               localUserID: localUserID,
                                               routingInfo: routingInfo,
                                               deviceUniqueIdentifier: deviceID,
                                               deviceSerialNumber: serialNumber,
                                               deviceDescription: serverFriendlyDescription,
                                               date: Date(),
                                               locale: .current,
                                               timeZone: .current)
            completion(.success(anisetteData))
        }
        catch
        {
            completion(.failure(error))
        }
    }
    
    func requestAnisetteData(from serverURL: URL, completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        // One-time passwords expire, so never serve them from a cache.
        var request = URLRequest(url: serverURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { (data, _, error) in
            do
            {
                let data = try Result<Data, Error>(data, error).get()
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AnisetteError.invalidServerResponse() }
                
                let anisetteData = try ALTAnisetteData(anisetteServerResponse: json)
                completion(.success(anisetteData))
            }
            catch
            {
                Logger.main.error("Failed to fetch anisette data from server \(serverURL.absoluteString, privacy: .public). \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    func requestAnisetteDataFromXPCService(completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        guard let proxy = self.xpcConnection.remoteObjectProxyWithErrorHandler({ (error) in
            print("Anisette XPC Error:", error)
            completion(.failure(error))
        }) as? AltXPCProtocol else { return }
        
        proxy.requestAnisetteData { (anisetteData, error) in
            guard let anisetteData else {
                // AltXPC returns nil anisette data when AuthKit won't provide it, which isn't necessarily accompanied by an error.
                completion(.failure(error ?? ALTServerError(.invalidAnisetteData)))
                return
            }
            
            anisetteData.sanitize(byReplacingBundleID: Bundle.ID.altXPC)
            completion(.success(anisetteData))
        }
    }
    
    func requestAnisetteDataFromPlugin(completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        let requestUUID = UUID().uuidString
        self.anisetteDataCompletionHandlers[requestUUID] = completion
        
        let timer = Timer(timeInterval: 1.0, repeats: false) { (timer) in
            self.finishRequest(forUUID: requestUUID, result: .failure(ALTServerError(.pluginNotFound)))
        }
        self.anisetteDataTimers[requestUUID] = timer
        
        RunLoop.main.add(timer, forMode: .default)
        
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.rileytestut.AltServer.FetchAnisetteData"), object: nil, userInfo: ["requestUUID": requestUUID], options: .deliverImmediately)
    }
    
    @objc func handleAnisetteDataResponse(_ notification: Notification)
    {
        guard let userInfo = notification.userInfo, let requestUUID = userInfo["requestUUID"] as? String else { return }
                
        if
            let archivedAnisetteData = userInfo["anisetteData"] as? Data,
            let anisetteData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ALTAnisetteData.self, from: archivedAnisetteData)
        {
            anisetteData.sanitize(byReplacingBundleID: Bundle.ID.mail)
            self.finishRequest(forUUID: requestUUID, result: .success(anisetteData))
        }
        else
        {
            self.finishRequest(forUUID: requestUUID, result: .failure(ALTServerError(.invalidAnisetteData)))
        }
    }
    
    func finishRequest(forUUID requestUUID: String, result: Result<ALTAnisetteData, Error>)
    {
        let completionHandler = self.anisetteDataCompletionHandlers[requestUUID]
        self.anisetteDataCompletionHandlers[requestUUID] = nil
        
        let timer = self.anisetteDataTimers[requestUUID]
        self.anisetteDataTimers[requestUUID] = nil
        
        timer?.invalidate()
        completionHandler?(result)
    }
}
