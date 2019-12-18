//
//  Bundle+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

public extension Bundle
{
    struct Info
    {
        public static let deviceID = "ALTDeviceID"
        public static let serverID = "ALTServerID"
        public static let certificateID = "ALTCertificateID"
        public static let appGroups = "ALTAppGroups"
        
        public static let urlTypes = "CFBundleURLTypes"
        public static let exportedUTIs = "UTExportedTypeDeclarations"
    }
}

public extension Bundle
{
    var infoPlistURL: URL {
        let infoPlistURL = self.bundleURL.appendingPathComponent("Info.plist")
        return infoPlistURL
    }
    
    var certificateURL: URL {
        let infoPlistURL = self.bundleURL.appendingPathComponent("ALTCertificate.p12")
        return infoPlistURL
    }
}
