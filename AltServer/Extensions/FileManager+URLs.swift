//
//  FileManager+URLs.swift
//  AltServer
//
//  Created by Riley Testut on 2/23/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import Foundation

extension FileManager
{
    var altserverDirectory: URL {
        let applicationSupportDirectoryURL = self.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        
        let altserverDirectoryURL = applicationSupportDirectoryURL.appendingPathComponent("com.rileytestut.AltServer")
        return altserverDirectoryURL
    }
    
    var certificatesDirectory: URL {
        let certificatesDirectoryURL = self.altserverDirectory.appendingPathComponent("Certificates")
        return certificatesDirectoryURL
    }
    
    var developerDisksDirectory: URL {
        let developerDisksDirectoryURL = self.altserverDirectory.appendingPathComponent("DeveloperDiskImages")
        return developerDisksDirectoryURL
    }
}
