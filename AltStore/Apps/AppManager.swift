//
//  AppManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import UIKit

import AltSign
import AltKit

import Roxas

extension AppManager
{
    enum AppError: LocalizedError
    {
        case unknown
        case missingUDID
        case noServersFound
        case missingPrivateKey
        case missingCertificate
        case notAuthenticated
        
        case multipleCertificates
        case multipleTeams
        
        case download(URLError)
        case authentication(Error)
        case fetchingSigningResources(Error)
        case prepare(Error)
        case install(Error)
        
        var errorDescription: String? {
            switch self
            {
            case .unknown: return "An unknown error occured."
            case .missingUDID: return "The UDID for this device is unknown."
            case .noServersFound: return "An active AltServer could not be found."
            case .missingPrivateKey: return "A valid private key must be provided."
            case .missingCertificate: return "A valid certificate must be provided."
            case .notAuthenticated: return "You must be logged in with your Apple ID to install apps."
            case .multipleCertificates: return "You must select a certificate to use to install apps."
            case .multipleTeams: return "You must select a team to use to install apps."
            case .download(let error): return error.localizedDescription
            case .authentication(let error): return error.localizedDescription
            case .fetchingSigningResources(let error): return error.localizedDescription
            case .prepare(let error): return error.localizedDescription
            case .install(let error): return error.localizedDescription
            }
        }
    }
}

class AppManager
{
    static let shared = AppManager()
    
    private let session = URLSession(configuration: .default)
    private let operationQueue = OperationQueue()
    
    private init()
    {
        self.operationQueue.name = "com.rileytestut.AltStore.AppManager"
    }
}

extension AppManager
{
    func update()
    {
        #if targetEnvironment(simulator)
        // Apps aren't ever actually installed to simulator, so just do nothing rather than delete them from database.
        return
        #else
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
        
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
        
        do
        {
            let installedApps = try context.fetch(fetchRequest)
            for app in installedApps
            {
                if UIApplication.shared.canOpenURL(app.openAppURL)
                {
                    // App is still installed, good!
                }
                else
                {
                    context.delete(app)
                }
            }
            
            try context.save()
        }
        catch
        {
            print("Error while fetching installed apps")
        }
        
        #endif
    }
    
    func authenticate(presentingViewController: UIViewController?, completionHandler: @escaping (Result<(ALTTeam, ALTCertificate), Error>) -> Void)
    {
        let authenticationOperation = AuthenticationOperation(presentingViewController: presentingViewController)
        authenticationOperation.resultHandler = { (result) in
            completionHandler(result)
        }
        self.operationQueue.addOperation(authenticationOperation)
    }
}

extension AppManager
{
    func install(_ app: App, presentingViewController: UIViewController, completionHandler: @escaping (Result<InstalledApp, AppError>) -> Void)
    {
        let ipaURL = InstalledApp.ipaURL(for: app)
        
        let backgroundTaskID = RSTBeginBackgroundTask("com.rileytestut.AltStore.InstallApp")
        
        func finish(_ result: Result<InstalledApp, AppError>)
        {
            completionHandler(result)
            
            RSTEndBackgroundTask(backgroundTaskID)
        }
        
        // Download app
        self.downloadApp(from: app.downloadURL) { (result) in
            let result = result.flatMap { (fileURL) -> Result<Void, URLError> in
                // Copy downloaded app to proper location
                let result = Result { try FileManager.default.copyItem(at: fileURL, to: ipaURL, shouldReplace: true) }
                return result.mapError { _ in URLError(.cannotWriteToFile) }
            }
            
            switch result
            {
            case .failure(let error): finish(.failure(.download(error)))
            case .success:
                // Authenticate
                self.authenticate(presentingViewController: presentingViewController) { (result) in
                    switch result
                    {
                    case .failure(let error): finish(.failure(.authentication(error)))
                    case .success(let team, let certificate):
                        
                        // Fetch provisioning profile
                        self.prepareProvisioningProfile(for: app, team: team) { (result) in
                            switch result
                            {
                            case .failure(let error): finish(.failure(.fetchingSigningResources(error)))
                            case .success(let profile):
                                
                                // Prepare app
                                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                                    let app = context.object(with: app.objectID) as! App
                                    
                                    let installedApp = InstalledApp(app: app,
                                                                    bundleIdentifier: profile.appID.bundleIdentifier,
                                                                    expirationDate: profile.expirationDate,
                                                                    context: context)
                                    
                                    let signer = ALTSigner(team: team, certificate: certificate)
                                    self.prepare(installedApp, provisioningProfile: profile, signer: signer) { (result) in
                                        switch result
                                        {
                                        case .failure(let error): finish(.failure(.prepare(error)))
                                        case .success(let resignedURL):
                                            
                                            // Send app to server
                                            context.perform {
                                                self.sendAppToServer(fileURL: resignedURL, identifier: installedApp.bundleIdentifier) { (result) in
                                                    switch result
                                                    {
                                                    case .failure(let error): finish(.failure(.install(error)))
                                                    case .success:
                                                        context.perform {
                                                            finish(.success(installedApp))
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func refresh(_ app: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        self.refresh([app], presentingViewController: presentingViewController) { (result) in
            do
            {
                guard let (_, result) = try result.get().first else { throw AppError.unknown }
                completionHandler(result)
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func refreshAllApps(presentingViewController: UIViewController?, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], AppError>) -> Void)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            do
            {
                let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
                fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.app)]
                
                let installedApps = try context.fetch(fetchRequest)
                self.refresh(installedApps, presentingViewController: presentingViewController) { (result) in
                    context.perform { // keep context alive
                        completionHandler(result)
                    }
                }
            }
            catch
            {
                completionHandler(.failure(.prepare(error)))
            }
        }
    }
    
    private func refresh<T: Collection>(_ installedApps: T, presentingViewController: UIViewController?, completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], AppError>) -> Void) where T.Element == InstalledApp
    {
        let backgroundTaskID = RSTBeginBackgroundTask("com.rileytestut.AltStore.RefreshApps")
        
        func finish(_ result: Result<[String: Result<InstalledApp, Error>], AppError>)
        {
            completionHandler(result)
            
            RSTEndBackgroundTask(backgroundTaskID)
        }
        
        guard !ServerManager.shared.discoveredServers.isEmpty else { return finish(.failure(.noServersFound)) }
        
        // Authenticate
        self.authenticate(presentingViewController: presentingViewController) { (result) in
            switch result
            {
            case .failure(let error): finish(.failure(.authentication(error)))
            case .success(let team, let certificate):
                
                // Sign
                let signer = ALTSigner(team: team, certificate: certificate)
                
                let dispatchGroup = DispatchGroup()
                var results = [String: Result<InstalledApp, Error>]()
                
                let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                
                for app in installedApps
                {
                    dispatchGroup.enter()
                    
                    app.managedObjectContext?.perform {
                        let bundleIdentifier = app.bundleIdentifier
                        print("Refreshing App:", bundleIdentifier)
                        
                        self.refresh(app, signer: signer, context: context) { (result) in
                            print("Refreshed App: \(bundleIdentifier).", result)
                            results[bundleIdentifier] = result
                            dispatchGroup.leave()
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .global()) {
                    context.perform {
                        finish(.success(results))
                    }
                }
            }
        }
    }
}

private extension AppManager
{
    func downloadApp(from url: URL, completionHandler: @escaping (Result<URL, URLError>) -> Void)
    {
        let downloadTask = self.session.downloadTask(with: url) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                completionHandler(.success(fileURL))
            }
            catch let error as URLError
            {
                completionHandler(.failure(error))
            }
            catch
            {
                completionHandler(.failure(URLError(.unknown)))
            }
        }
        
        downloadTask.resume()
    }
    
    func prepareProvisioningProfile(for app: App, team: ALTTeam, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        guard let udid = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.deviceID) as? String else { return completionHandler(.failure(AppError.missingUDID)) }
        
        let device = ALTDevice(name: UIDevice.current.name, identifier: udid)
        self.register(device, team: team) { (result) in
            do
            {
                _ = try result.get()
                
                app.managedObjectContext?.perform {
                    self.register(app, with: team) { (result) in
                        do
                        {
                            let appID = try result.get()
                            self.fetchProvisioningProfile(for: appID, team: team) { (result) in
                                do
                                {
                                    let provisioningProfile = try result.get()
                                    completionHandler(.success(provisioningProfile))
                                }
                                catch
                                {
                                    completionHandler(.failure(error))
                                }
                            }
                        }
                        catch
                        {
                            completionHandler(.failure(error))
                        }
                    }
                }
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func prepare(_ installedApp: InstalledApp, provisioningProfile: ALTProvisioningProfile, signer: ALTSigner, completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        do
        {
            let refreshedAppDirectory = installedApp.directoryURL.appendingPathComponent("Refreshed", isDirectory: true)
            
            if FileManager.default.fileExists(atPath: refreshedAppDirectory.path)
            {
                try FileManager.default.removeItem(at: refreshedAppDirectory)
            }
            try FileManager.default.createDirectory(at: refreshedAppDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let appBundleURL = try FileManager.default.unzipAppBundle(at: installedApp.ipaURL, toDirectory: refreshedAppDirectory)
            guard let bundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }
            
            guard var infoDictionary = NSDictionary(contentsOf: bundle.infoPlistURL) as? [String: Any] else { throw ALTError(.missingInfoPlist) }
            
            var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
            
            let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                     "CFBundleURLName": installedApp.bundleIdentifier,
                                     "CFBundleURLSchemes": [installedApp.openAppURL.scheme!]] as [String : Any]
            allURLSchemes.append(altstoreURLScheme)
            
            infoDictionary[Bundle.Info.urlTypes] = allURLSchemes
            
            try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
            
            signer.signApp(at: appBundleURL, provisioningProfile: provisioningProfile) { (success, error) in
                do
                {
                    try Result(success, error).get()
                    
                    let resignedURL = try FileManager.default.zipAppBundle(at: appBundleURL)
                    completionHandler(.success(resignedURL))
                }
                catch
                {
                    completionHandler(.failure(error))
                }
            }
        }
        catch
        {
            completionHandler(.failure(error))
        }
    }
    
    func sendAppToServer(fileURL: URL, identifier: String, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        guard let server = ServerManager.shared.discoveredServers.first else { return completionHandler(.failure(AppError.noServersFound)) }
        
        server.installApp(at: fileURL, identifier: identifier) { (result) in
            let result = result.mapError { $0 as Error }
            completionHandler(result)
        }
    }
}

private extension AppManager
{
    func register(_ device: ALTDevice, team: ALTTeam, completionHandler: @escaping (Result<ALTDevice, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchDevices(for: team) { (devices, error) in
            do
            {
                let devices = try Result(devices, error).get()
                
                if let device = devices.first(where: { $0.identifier == device.identifier })
                {
                    completionHandler(.success(device))
                }
                else
                {
                    ALTAppleAPI.shared.registerDevice(name: device.name, identifier: device.identifier, team: team) { (device, error) in
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
    
    func register(_ app: App, with team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
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
    
    func refresh(_ installedApp: InstalledApp, signer: ALTSigner, context: NSManagedObjectContext, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        self.prepareProvisioningProfile(for: installedApp.app, team: signer.team) { (result) in
            switch result
            {
            case .failure(let error): completionHandler(.failure(error))
            case .success(let profile):
                
                installedApp.managedObjectContext?.perform {
                    self.prepare(installedApp, provisioningProfile: profile, signer: signer) { (result) in
                        switch result
                        {
                        case .failure(let error): completionHandler(.failure(error))
                        case .success(let resignedURL):
                            
                            // Send app to server
                            installedApp.managedObjectContext?.perform {
                                self.sendAppToServer(fileURL: resignedURL, identifier: installedApp.bundleIdentifier) { (result) in
                                    context.perform {
                                        switch result
                                        {
                                        case .success:
                                            let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                                            installedApp.expirationDate = profile.expirationDate
                                            completionHandler(.success(installedApp))
                                            
                                        case .failure(let error):
                                            completionHandler(.failure(error))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
