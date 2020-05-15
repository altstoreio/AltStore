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
class ResignAppOperation: ResultOperation<ALTApplication>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 3
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let app = self.context.app,
            let profiles = self.context.provisioningProfiles,
            let team = self.context.team,
            let certificate = self.context.certificate
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // Prepare app bundle
        let prepareAppProgress = Progress.discreteProgress(totalUnitCount: 2)
        self.progress.addChild(prepareAppProgress, withPendingUnitCount: 3)
        
        let prepareAppBundleProgress = self.prepareAppBundle(for: app, profiles: profiles) { (result) in
            guard let appBundleURL = self.process(result) else { return }
            
            print("Resigning App:", self.context.bundleIdentifier)
            
            // Resign app bundle
            let resignProgress = self.resignAppBundle(at: appBundleURL, team: team, certificate: certificate, profiles: Array(profiles.values)) { (result) in
                guard let resignedURL = self.process(result) else { return }
                
                // Finish
                do
                {
                    let destinationURL = InstalledApp.refreshedIPAURL(for: app)
                    try FileManager.default.copyItem(at: resignedURL, to: destinationURL, shouldReplace: true)
                    
                    // Use appBundleURL since we need an app bundle, not .ipa.
                    guard let resignedApplication = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
                    self.finish(.success(resignedApplication))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
            prepareAppProgress.addChild(resignProgress, withPendingUnitCount: 1)
        }
        prepareAppProgress.addChild(prepareAppBundleProgress, withPendingUnitCount: 1)
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
    func prepareAppBundle(for app: ALTApplication, profiles: [String: ALTProvisioningProfile], completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let progress = Progress.discreteProgress(totalUnitCount: 1)
        
        let bundleIdentifier = app.bundleIdentifier
        let openURL = InstalledApp.openAppURL(for: app)
        
        let fileURL = app.fileURL
        
        func prepare(_ bundle: Bundle, additionalInfoDictionaryValues: [String: Any] = [:]) throws
        {
            guard let identifier = bundle.bundleIdentifier else { throw ALTError(.missingAppBundle) }
            guard let profile = profiles[identifier] else { throw ALTError(.missingProvisioningProfile) }
            guard var infoDictionary = bundle.infoDictionary else { throw ALTError(.missingInfoPlist) }
            
            infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
            infoDictionary[Bundle.Info.altBundleID] = identifier
            
            for (key, value) in additionalInfoDictionaryValues
            {
                infoDictionary[key] = value
            }
            
            if let appGroups = profile.entitlements[.appGroups] as? [String]
            {
                infoDictionary[Bundle.Info.appGroups] = appGroups
            }
            
            // Add app-specific exported UTI so we can check later if this app (extension) is installed or not.
            let installedAppUTI = ["UTTypeConformsTo": [],
                                   "UTTypeDescription": "AltStore Installed App",
                                   "UTTypeIconFiles": [],
                                   "UTTypeIdentifier": InstalledApp.installedAppUTI(forBundleIdentifier: profile.bundleIdentifier),
                                   "UTTypeTagSpecification": [:]] as [String : Any]
            
            var exportedUTIs = infoDictionary[Bundle.Info.exportedUTIs] as? [[String: Any]] ?? []
            exportedUTIs.append(installedAppUTI)
            infoDictionary[Bundle.Info.exportedUTIs] = exportedUTIs
            
            try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
        }
        
        DispatchQueue.global().async {
            do
            {
                let appBundleURL = self.context.temporaryDirectory.appendingPathComponent("App.app")
                try FileManager.default.copyItem(at: fileURL, to: appBundleURL)
                
                // Become current so we can observe progress from unzipAppBundle().
                progress.becomeCurrent(withPendingUnitCount: 1)
                
                guard let appBundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }
                guard let infoDictionary = appBundle.infoDictionary else { throw ALTError(.missingInfoPlist) }
                
                var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
                
                let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                         "CFBundleURLName": bundleIdentifier,
                                         "CFBundleURLSchemes": [openURL.scheme!]] as [String : Any]
                allURLSchemes.append(altstoreURLScheme)
                
                var additionalValues: [String: Any] = [Bundle.Info.urlTypes: allURLSchemes]

                if self.context.bundleIdentifier == StoreApp.altstoreAppID || StoreApp.alternativeAltStoreAppIDs.contains(self.context.bundleIdentifier)
                {
                    guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { throw OperationError.unknownUDID }
                    additionalValues[Bundle.Info.deviceID] = udid
                    additionalValues[Bundle.Info.serverID] = UserDefaults.standard.preferredServerID
                    
                    if
                        let data = Keychain.shared.signingCertificate,
                        let signingCertificate = ALTCertificate(p12Data: data, password: nil),
                        let encryptingPassword = Keychain.shared.signingCertificatePassword
                    {
                        additionalValues[Bundle.Info.certificateID] = signingCertificate.serialNumber
                        
                        let encryptedData = signingCertificate.encryptedP12Data(withPassword: encryptingPassword)
                        try encryptedData?.write(to: appBundle.certificateURL, options: .atomic)
                    }
                    else
                    {
                        // The embedded certificate + certificate identifier are already in app bundle, no need to update them.
                    }
                }
                
                // Prepare app
                try prepare(appBundle, additionalInfoDictionaryValues: additionalValues)
                
                if let directory = appBundle.builtInPlugInsURL, let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
                {
                    for case let fileURL as URL in enumerator
                    {
                        guard let appExtension = Bundle(url: fileURL) else { throw ALTError(.missingAppBundle) }
                        try prepare(appExtension)
                    }
                }
                
                completionHandler(.success(appBundleURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        return progress
    }
    
    func resignAppBundle(at fileURL: URL, team: ALTTeam, certificate: ALTCertificate, profiles: [ALTProvisioningProfile], completionHandler: @escaping (Result<URL, Error>) -> Void) -> Progress
    {
        let signer = ALTSigner(team: team, certificate: certificate)
        let progress = signer.signApp(at: fileURL, provisioningProfiles: profiles) { (success, error) in
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
