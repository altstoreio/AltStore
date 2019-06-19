//
//  ResignAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

import AltSign

@objc(ResignAppOperation)
class ResignAppOperation: ResultOperation<URL>
{
    let installedApp: InstalledApp
    private var context: NSManagedObjectContext?
    
    var signer: ALTSigner?
    
    init(installedApp: InstalledApp)
    {
        self.installedApp = installedApp
        self.context = installedApp.managedObjectContext
        
        super.init()
        
        self.progress.totalUnitCount = 3
    }
    
    override func main()
    {
        super.main()
        
        guard let context = self.context else { return self.finish(.failure(OperationError.appNotFound)) }
        guard let signer = self.signer else { return self.finish(.failure(OperationError.notAuthenticated)) }
        
        context.perform {
            // Register Device
            self.registerCurrentDevice(for: signer.team) { (result) in
                guard let _ = self.process(result) else { return }
                
                // Register App
                context.perform {
                    self.register(self.installedApp.app, team: signer.team) { (result) in
                        guard let appID = self.process(result) else { return }
                        
                        // Fetch Provisioning Profile
                        self.fetchProvisioningProfile(for: appID, team: signer.team) { (result) in
                            guard let profile = self.process(result) else { return }
                            
                            // Prepare app bundle
                            context.perform {
                                let prepareAppProgress = Progress.discreteProgress(totalUnitCount: 2)
                                self.progress.addChild(prepareAppProgress, withPendingUnitCount: 3)
                                
                                let prepareAppBundleProgress = self.prepareAppBundle(for: self.installedApp) { (result) in
                                    guard let appBundleURL = self.process(result) else { return }
                                    
                                    // Resign app bundle
                                    let resignProgress = self.resignAppBundle(at: appBundleURL, signer: signer, profile: profile) { (result) in
                                        guard let resignedURL = self.process(result) else { return }
                                        
                                        // Finish
                                        context.perform {
                                            do
                                            {
                                                try FileManager.default.copyItem(at: resignedURL, to: self.installedApp.refreshedIPAURL, shouldReplace: true)
                                                
                                                let refreshedDirectory = resignedURL.deletingLastPathComponent()
                                                try? FileManager.default.removeItem(at: refreshedDirectory)
                                                
                                                self.finish(.success(self.installedApp.refreshedIPAURL))
                                            }
                                            catch
                                            {
                                                self.finish(.failure(error))
                                            }
                                        }
                                    }
                                    prepareAppProgress.addChild(resignProgress, withPendingUnitCount: 1)
                                }
                                prepareAppProgress.addChild(prepareAppBundleProgress, withPendingUnitCount: 1)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func process<T>(_ result: Result<T, Error>) -> T?
    {
        switch result
        {
        case .failure(let error):
            self.finish(.failure(error))
            return nil
            
        case .success(let value):
            guard !self.isCancelled else {
                self.finish(.failure(OperationError.cancelled))
                return nil
            }
            
            return value
        }
    }
}

private extension ResignAppOperation
{
    func registerCurrentDevice(for team: ALTTeam, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else {
            return completionHandler(.failure(OperationError.unknownUDID))
        }
        
        ALTAppleAPI.shared.fetchDevices(for: team) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == udid })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: UIDevice.current.name, identifier: udid, team: team) { (device, error) in
                        completionHandler(Result(device, error))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func register(_ app: App, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let appName = app.name
        let bundleID = "com.\(team.identifier).\(app.identifier)"
        
        ALTAppleAPI.shared.fetchAppIDs(for: team) { (appIDs, error) in
            do
            {
                let appIDs = try Result(appIDs, error).get()
                
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleID })
                {
                    completionHandler(.success(appID))
                }
                else
                {
                    ALTAppleAPI.shared.addAppID(withName: appName, bundleIdentifier: bundleID, team: team) { (appID, error) in
                        completionHandler(Result(appID, error))
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func fetchProvisioningProfile(for appID: ALTAppID, team: ALTTeam, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team) { (profile, error) in
            completionHandler(Result(profile, error))
        }
    }
    
    func prepareAppBundle(for installedApp: InstalledApp, completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 1)
        
        let refreshedAppDirectory = installedApp.directoryURL.appendingPathComponent("Refreshed", isDirectory: true)
        let ipaURL = installedApp.ipaURL
        let bundleIdentifier = installedApp.bundleIdentifier
        let openURL = installedApp.openAppURL
        let appIdentifier = installedApp.app.identifier
        
        DispatchQueue.global().async {
            do
            {
                if FileManager.default.fileExists(atPath: refreshedAppDirectory.path)
                {
                    try FileManager.default.removeItem(at: refreshedAppDirectory)
                }
                try FileManager.default.createDirectory(at: refreshedAppDirectory, withIntermediateDirectories: true, attributes: nil)
                
                // Become current so we can observe progress from unzipAppBundle().
                progress.becomeCurrent(withPendingUnitCount: 1)
                
                let appBundleURL = try FileManager.default.unzipAppBundle(at: ipaURL, toDirectory: refreshedAppDirectory)
                guard let bundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }
                
                guard var infoDictionary = NSDictionary(contentsOf: bundle.infoPlistURL) as? [String: Any] else { throw ALTError(.missingInfoPlist) }
                
                var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
                
                let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                         "CFBundleURLName": bundleIdentifier,
                                         "CFBundleURLSchemes": [openURL.scheme!]] as [String : Any]
                allURLSchemes.append(altstoreURLScheme)
                
                infoDictionary[Bundle.Info.urlTypes] = allURLSchemes
                
                if appIdentifier == App.altstoreAppID
                {
                    guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
                    infoDictionary[Bundle.Info.deviceID] = udid
                }
                
                try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
                
                completionHandler(.success(appBundleURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        return progress
    }
    
    func resignAppBundle(at fileURL: URL, signer: ALTSigner, profile: ALTProvisioningProfile, completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let progress = signer.signApp(at: fileURL, provisioningProfile: profile) { (success, error) in
            do
            {
                try Result(success, error).get()
                
                let ipaURL = try FileManager.default.zipAppBundle(at: fileURL)
                completionHandler(.success(ipaURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        return progress
    }
}
