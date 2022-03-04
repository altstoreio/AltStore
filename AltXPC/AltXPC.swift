//
//  AltXPC.swift
//  AltXPC
//
//  Created by Riley Testut on 12/3/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

@objc(AltXPC)
class AltXPC: NSObject, AltXPCProtocol
{
    func ping(_ completionHandler: @escaping () -> Void)
    {
        completionHandler()
    }
    
    func requestAnisetteData(completionHandler: @escaping (ALTAnisetteData?, Error?) -> Void)
    {
        let anisetteData = ALTPluginService.shared.requestAnisetteData()
        completionHandler(anisetteData, nil)
    }
}
