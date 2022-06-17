//
//  AnisetteDataManager.swift
//  AltServer
//
//  Created by Riley Testut on 11/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AppKit

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
        if #available(macOS 10.15, *)
        {
            self.requestAnisetteDataFromXPCService { (result) in
                do
                {
                    let anisetteData = try result.get()
                    completion(.success(anisetteData))
                }
                catch CocoaError.xpcConnectionInterrupted
                {
                    // SIP and/or AMFI are not disabled, so fall back to Mail plug-in.
                    self.requestAnisetteDataFromPlugin { (result) in
                        completion(result)
                    }
                }
                catch
                {
                    completion(.failure(error))
                }
            }
        }
        else
        {
            self.requestAnisetteDataFromPlugin { (result) in
                completion(result)
            }
        }
    }
    
    func isXPCAvailable(completion: @escaping (Bool) -> Void)
    {
        guard let proxy = self.xpcConnection.remoteObjectProxyWithErrorHandler({ (error) in
            completion(false)
        }) as? AltXPCProtocol else { return }
        
        proxy.ping {
            completion(true)
        }
    }
}

private extension AnisetteDataManager
{
    @available(macOS 10.15, *)
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
        
        if let mailApp = FileManager.default.urls(
                        for: .applicationDirectory,
                        in: .systemDomainMask
                    ).first?.appendingPathComponent("Mail.app") {
                        NSWorkspace.shared.open(mailApp)
                    }
        
        let timer = Timer(timeInterval: 5.0, repeats: false) { (timer) in
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
