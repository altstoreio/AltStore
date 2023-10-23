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

private extension CFNotificationName
{
    static let updatedProvisioningProfiles = CFNotificationName("MISProvisioningProfileRemoved" as CFString)
}

struct AppManager
{
    static let shared = AppManager()
    
    private let appQueue = DispatchQueue(label: "com.rileytestut.AltDaemon.appQueue", qos: .userInitiated)
    private let profilesQueue = OperationQueue()
    
    private let fileCoordinator = NSFileCoordinator()
    
    private init()
    {
        self.profilesQueue.name = "com.rileytestut.AltDaemon.profilesQueue"
        self.profilesQueue.qualityOfService = .userInitiated
    }
    
    func installApp(at fileURL: URL, bundleIdentifier: String, activeProfiles: Set<String>?, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.appQueue.async {
            let lsApplicationWorkspace = unsafeBitCast(NSClassFromString("LSApplicationWorkspace")!, to: LSApplicationWorkspace.Type.self)
            
            let options = ["CFBundleIdentifier": bundleIdentifier, "AllowInstallLocalProvisioned": NSNumber(value: true)] as [String : Any]
            let result = Result { try lsApplicationWorkspace.default.installApplication(fileURL, withOptions: options) }
            
            completionHandler(result)
        }
    }
    
    func removeApp(forBundleIdentifier bundleIdentifier: String, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.appQueue.async {
            let lsApplicationWorkspace = unsafeBitCast(NSClassFromString("LSApplicationWorkspace")!, to: LSApplicationWorkspace.Type.self)
            lsApplicationWorkspace.default.uninstallApplication(bundleIdentifier, withOptions: nil)
            
            completionHandler(.success(()))
        }
    }
    
    func install(_ profiles: Set<ALTProvisioningProfile>, activeProfiles: Set<String>?, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let intent = NSFileAccessIntent.writingIntent(with: .profilesDirectoryURL, options: [])
        self.fileCoordinator.coordinate(with: [intent], queue: self.profilesQueue) { (error) in
            do
            {
                if let error = error
                {
                    throw error
                }
                
                let installingBundleIDs = Set(profiles.map(\.bundleIdentifier))
                
                let profileURLs = try FileManager.default.contentsOfDirectory(at: intent.url, includingPropertiesForKeys: nil, options: [])
                
                // Remove all inactive profiles (if active profiles are provided), and the previous profiles.
                for fileURL in profileURLs
                {
                    // Use memory mapping to reduce peak memory usage and stay within limit.
                    guard let profile = try? ALTProvisioningProfile(url: fileURL, options: [.mappedIfSafe]) else { continue }
                    
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
                
                completionHandler(.success(()))
            }
            catch
            {
                completionHandler(.failure(error))
            }
            
            // Notify system to prevent accidentally untrusting developer certificate.
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), .updatedProvisioningProfiles, nil, nil, true)
        }
    }
    
    func removeProvisioningProfiles(forBundleIdentifiers bundleIdentifiers: Set<String>, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        let intent = NSFileAccessIntent.writingIntent(with: .profilesDirectoryURL, options: [])
        self.fileCoordinator.coordinate(with: [intent], queue: self.profilesQueue) { (error) in
            do
            {
                let profileURLs = try FileManager.default.contentsOfDirectory(at: intent.url, includingPropertiesForKeys: nil, options: [])
                
                for fileURL in profileURLs
                {
                    guard let profile = ALTProvisioningProfile(url: fileURL) else { continue }
                    
                    if bundleIdentifiers.contains(profile.bundleIdentifier)
                    {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
                
                completionHandler(.success(()))
            }
            catch
            {
                completionHandler(.failure(error))
            }
            
            // Notify system to prevent accidentally untrusting developer certificate.
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), .updatedProvisioningProfiles, nil, nil, true)
        }
    }
}
