//
//  AnisetteDataManager.swift
//  AltServer
//
//  Created by Riley Testut on 11/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

class AnisetteDataManager: NSObject
{
    static let shared = AnisetteDataManager()
    
    private var anisetteDataCompletionHandlers: [String: (Result<ALTAnisetteData, Error>) -> Void] = [:]
    private var anisetteDataTimers: [String: Timer] = [:]
    
    private override init()
    {
        super.init()
        
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(AnisetteDataManager.handleAnisetteDataResponse(_:)), name: Notification.Name("com.rileytestut.AltServer.AnisetteDataResponse"), object: nil)
    }
    
    func requestAnisetteData(_ completion: @escaping (Result<ALTAnisetteData, Error>) -> Void)
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
}

private extension AnisetteDataManager
{
    @objc func handleAnisetteDataResponse(_ notification: Notification)
    {
        guard let userInfo = notification.userInfo, let requestUUID = userInfo["requestUUID"] as? String else { return }
                
        if
            let archivedAnisetteData = userInfo["anisetteData"] as? Data,
            let anisetteData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ALTAnisetteData.self, from: archivedAnisetteData)
        {
            if let range = anisetteData.deviceDescription.lowercased().range(of: "(com.apple.mail")
            {
                var adjustedDescription = anisetteData.deviceDescription[..<range.lowerBound]
                adjustedDescription += "(com.apple.dt.Xcode/3594.4.19)>"
                
                anisetteData.deviceDescription = String(adjustedDescription)
            }
            
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
