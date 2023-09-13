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
        self.requestAnisetteDataFromAOSKit { (result) in
            do
            {
                let anisetteData = try result.get()
                completion(.success(anisetteData))
            }
            catch let aosKitError
            {
                // Fall back to XPC in case SIP is disabled.
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
                                completion(.failure(aosKitError))
                            }
                        }
                    }
                    catch
                    {
                        Logger.main.error("Failed to fetch anisette data via XPC service. \(error.localizedDescription, privacy: .public)")
                        
                        // Return original error.
                        completion(.failure(aosKitError))
                    }
                }
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
    
    func requestAnisetteDataFromXPCService(completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
    {
        guard let proxy = self.xpcConnection.remoteObjectProxyWithErrorHandler({ (error) in
            print("Anisette XPC Error:", error)
            completion(.failure(error))
        }) as? AltXPCProtocol else { return }
        
        proxy.requestAnisetteData { (anisetteData, error) in
            anisetteData?.sanitize(byReplacingBundleID: Bundle.ID.altXPC)
            completion(Result(anisetteData, error))
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
