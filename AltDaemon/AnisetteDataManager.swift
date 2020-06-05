//
//  AnisetteDataManager.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign

private extension UserDefaults
{
    @objc var localUserID: String? {
        get { return self.string(forKey: #keyPath(UserDefaults.localUserID)) }
        set { self.set(newValue, forKey: #keyPath(UserDefaults.localUserID)) }
    }
}

struct AnisetteDataManager
{
    static let shared = AnisetteDataManager()
    
    private let dateFormatter = ISO8601DateFormatter()
    
    private init()
    {
        dlopen("/System/Library/PrivateFrameworks/AuthKit.framework/AuthKit", RTLD_NOW);
    }
    
    func requestAnisetteData() throws -> ALTAnisetteData
    {
        var request = URLRequest(url: URL(string: "https://developerservices2.apple.com/services/QH65B2/listTeams.action?clientId=XABBG36SBA")!)
        request.httpMethod = "POST"
        
        let akAppleIDSession = unsafeBitCast(NSClassFromString("AKAppleIDSession")!, to: AKAppleIDSession.Type.self)
        let akDevice = unsafeBitCast(NSClassFromString("AKDevice")!, to: AKDevice.Type.self)
        
        let session = akAppleIDSession.init(identifier: "com.apple.gs.xcode.auth")
        let headers = session.appleIDHeaders(for: request)
        
        let device = akDevice.current
        let date = self.dateFormatter.date(from: headers["X-Apple-I-Client-Time"] ?? "") ?? Date()
        
        var localUserID = UserDefaults.standard.localUserID
        if localUserID == nil
        {
            localUserID = UUID().uuidString
            UserDefaults.standard.localUserID = localUserID
        }
        
        let anisetteData = ALTAnisetteData(machineID: headers["X-Apple-I-MD-M"] ?? "",
                                           oneTimePassword: headers["X-Apple-I-MD"] ?? "",
                                           localUserID: headers["X-Apple-I-MD-LU"] ?? localUserID ?? "",
                                           routingInfo: UInt64(headers["X-Apple-I-MD-RINFO"] ?? "") ?? 0,
                                           deviceUniqueIdentifier: device.uniqueDeviceIdentifier,
                                           deviceSerialNumber: device.serialNumber,
                                           deviceDescription: "<MacBookPro15,1> <Mac OS X;10.15.2;19C57> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>",
                                           date: date,
                                           locale: .current,
                                           timeZone: .current)
        return anisetteData
    }
}
