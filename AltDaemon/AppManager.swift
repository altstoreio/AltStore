//
//  AppManager.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign

private extension URL
{
    static let profilesDirectoryURL = URL(fileURLWithPath: "/var/MobileDevice/ProvisioningProfiles", isDirectory: true)
}

struct AppManager
{
    static let shared = AppManager()
    
    private init()
    {
    }
    
    func installApp(at fileURL: URL, bundleIdentifier: String, activeProfiles: Set<String>?) throws
    {
        let lsApplicationWorkspace = unsafeBitCast(NSClassFromString("LSApplicationWorkspace")!, to: LSApplicationWorkspace.Type.self)
        
        let options = ["CFBundleIdentifier": bundleIdentifier, "AllowInstallLocalProvisioned": NSNumber(value: true)] as [String : Any]
        try lsApplicationWorkspace.default.installApplication(fileURL, withOptions: options)
    }
    
    func removeApp(forBundleIdentifier bundleIdentifier: String)
    {
        let lsApplicationWorkspace = unsafeBitCast(NSClassFromString("LSApplicationWorkspace")!, to: LSApplicationWorkspace.Type.self)
        lsApplicationWorkspace.default.uninstallApplication(bundleIdentifier, withOptions: nil)
    }
    
    func install(_ profiles: Set<ALTProvisioningProfile>, activeProfiles: Set<String>?) throws
    {
        let installingBundleIDs = Set(profiles.map(\.bundleIdentifier))
        
        let profileURLs = try FileManager.default.contentsOfDirectory(at: .profilesDirectoryURL, includingPropertiesForKeys: nil, options: [])
        
        // Remove all inactive profiles (if active profiles are provided), and the previous profiles.
        for fileURL in profileURLs
        {
            guard let profile = ALTProvisioningProfile(url: fileURL) else { continue }
            
            if installingBundleIDs.contains(profile.bundleIdentifier) || (activeProfiles?.contains(profile.bundleIdentifier) == false && profile.isFreeProvisioningProfile)
            {
                try FileManager.default.removeItem(at: fileURL)
            }
            else
            {
                print("Ignoring:", profile.bundleIdentifier, profile.uuid)
            }
        }
        
        for profile in profiles
        {
            let destinationURL = URL.profilesDirectoryURL.appendingPathComponent(profile.uuid.uuidString.lowercased())
            try profile.data.write(to: destinationURL, options: .atomic)
        }
    }
    
    func removeProvisioningProfiles(forBundleIdentifiers bundleIdentifiers: Set<String>) throws
    {
        let profileURLs = try FileManager.default.contentsOfDirectory(at: .profilesDirectoryURL, includingPropertiesForKeys: nil, options: [])
        
        for fileURL in profileURLs
        {
            guard let profile = ALTProvisioningProfile(url: fileURL) else { continue }
            
            if bundleIdentifiers.contains(profile.bundleIdentifier)
            {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}
