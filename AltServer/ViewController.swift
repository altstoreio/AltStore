//
//  ViewController.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa

enum InstallError: Error
{
    case invalidCredentials
    case noTeam
    case missingPrivateKey
    case missingCertificate
    
    var localizedDescription: String {
        switch self
        {
        case .invalidCredentials: return "The provided Apple ID and password are incorrect."
        case .noTeam: return "You are not a member of any developer teams."
        case .missingPrivateKey: return "The developer certificate's private key could not be found."
        case .missingCertificate: return "The developer certificate could not be found."
        }
    }
}

class ViewController: NSViewController
{
    @IBOutlet private var emailAddressTextField: NSTextField!
    @IBOutlet private var passwordTextField: NSSecureTextField!
    
    @IBOutlet private var devicesButton: NSPopUpButton!
    
    private var currentDevice: ALTDevice?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        ConnectionManager.shared.stateUpdateHandler = { (state) in
            DispatchQueue.main.async {
                switch state
                {
                case .notRunning: self.view.window?.title = ""
                case .connecting: self.view.window?.title = "Connecting...."
                case .running(let service): self.view.window?.title = service.name ?? ""
                case .failed(let error): self.view.window?.title = error.localizedDescription
                }
            }
        }
        
        ConnectionManager.shared.start()
        
        self.update()
    }
    
    func update()
    {
        self.devicesButton.removeAllItems()
        
        let devices = ALTDeviceManager.shared.connectedDevices
        
        if devices.isEmpty
        {
            self.devicesButton.addItem(withTitle: "No Connected Device")
        }
        else
        {
            for device in devices
            {
                self.devicesButton.addItem(withTitle: device.name)
            }
        }
        
        if let currentDevice = self.currentDevice, let index = devices.firstIndex(of: currentDevice)
        {
            self.devicesButton.selectItem(at: index)
        }
        else
        {
            self.currentDevice = devices.first
            self.devicesButton.selectItem(at: 0)
        }
    }
}

private extension ViewController
{
    @IBAction func installAltStore(_ sender: NSButton)
    {
        guard let device = self.currentDevice else { return }
        guard !self.emailAddressTextField.stringValue.isEmpty, !self.passwordTextField.stringValue.isEmpty else { return }
        
        self.installAltStore(to: device)
    }
    
    @IBAction func chooseDevice(_ sender: NSPopUpButton)
    {
        let devices = ALTDeviceManager.shared.connectedDevices
        guard !devices.isEmpty else { return }
        
        let index = sender.indexOfSelectedItem
        
        let device = devices[index]
        self.currentDevice = device
    }
}

private extension ViewController
{
    func installAltStore(to device: ALTDevice)
    {
        let destinationDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        func finish(_ error: Error?, title: String = "")
        {
            DispatchQueue.main.async {
                let alert = NSAlert()
                
                if let error = error
                {
                    alert.messageText = title
                    alert.informativeText = error.localizedDescription
                }
                else
                {
                    alert.messageText = NSLocalizedString("Successfully installed AltStore!", comment: "")
                }
                
                alert.runModal()
            }
            
            try? FileManager.default.removeItem(at: destinationDirectoryURL)
        }
        
        self.authenticate() { (result) in
            do
            {
                let account = try result.get()
                self.fetchTeam(for: account) { (result) in
                    do
                    {
                        let team = try result.get()
                        
                        self.register(device, team: team) { (result) in
                            do
                            {
                                let device = try result.get()
                                
                                self.fetchCertificate(for: team) { (result) in
                                    do
                                    {
                                        let certificate = try result.get()
                                        
                                        self.downloadApp { (result) in
                                            do
                                            {
                                                let fileURL = try result.get()
                                                
                                                try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                                                
                                                let appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: destinationDirectoryURL)
                                                
                                                guard let application = ALTApplication(fileURL: appBundleURL) else { throw ALTError(.invalidApp) }
                                                
                                                self.registerAppID(name: "AltStore", identifier: "com.rileytestut.AltStore", team: team) { (result) in
                                                    do
                                                    {
                                                        let appID = try result.get()
                                                        
                                                        self.updateFeatures(for: appID, app: application, team: team) { (result) in
                                                            do
                                                            {
                                                                let appID = try result.get()
                                                                
                                                                self.fetchProvisioningProfile(for: appID, team: team) { (result) in
                                                                    do
                                                                    {
                                                                        let provisioningProfile = try result.get()
                                                                        
                                                                        self.install(application, to: device, team: team, appID: appID, certificate: certificate, profile: provisioningProfile) { (result) in
                                                                            finish(result.error, title: "Failed to Install AltStore")
                                                                        }
                                                                    }
                                                                    catch
                                                                    {
                                                                        finish(error, title: "Failed to Fetch Provisioning Profile")
                                                                    }
                                                                }
                                                            }
                                                            catch
                                                            {
                                                                finish(error, title: "Failed to Update App ID")
                                                            }
                                                        }
                                                    }
                                                    catch
                                                    {
                                                        finish(error, title: "Failed to Register App")
                                                    }
                                                }
                                            }
                                            catch
                                            {
                                                finish(error, title: "Failed to Download AltStore")
                                                return
                                            }
                                        }
                                    }
                                    catch
                                    {
                                        finish(error, title: "Failed to Fetch Certificate")
                                    }
                                }
                            }
                            catch
                            {
                                finish(error, title: "Failed to Register Device")
                            }
                        }
                    }
                    catch
                    {
                        finish(error, title: "Failed to Fetch Team")
                    }
                }
            }
            catch
            {
                finish(error, title: "Failed to Authenticate")
            }
        }
    }
    
    func downloadApp(completionHandler: @escaping (Result<URL, Error>) -> Void)
    {
        let appURL = URL(string: "https://www.dropbox.com/s/w1gn9iztlqvltyp/AltStore.ipa?dl=1")!
        
        let downloadTask = URLSession.shared.downloadTask(with: appURL) { (fileURL, response, error) in
            do
            {
                let (fileURL, _) = try Result((fileURL, response), error).get()
                completionHandler(.success(fileURL))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
        
        downloadTask.resume()
    }
    
    func authenticate(completionHandler: @escaping (Result<ALTAccount, Error>) -> Void)
    {
        ALTAppleAPI.shared.authenticate(appleID: self.emailAddressTextField.stringValue, password: self.passwordTextField.stringValue) { (account, error) in
            let result = Result(account, error)
            completionHandler(result)
        }
    }
    
    func fetchTeam(for account: ALTAccount, completionHandler: @escaping (Result<ALTTeam, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchTeams(for: account) { (teams, error) in
            do
            {
                let teams = try Result(teams, error).get()
                guard let team = teams.first else { throw InstallError.noTeam }
                
                completionHandler(.success(team))
            }
            catch
            {
                completionHandler(.failure(error))
            }
        }
    }
    
    func fetchCertificate(for team: ALTTeam, completionHandler: @escaping (Result<ALTCertificate, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
            do
            {
                let certificates = try Result(certificates, error).get()
                
                if let certificate = certificates.first
                {
                    ALTAppleAPI.shared.revoke(certificate, for: team) { (success, error) in
                        do
                        {
                            try Result(success, error).get()
                            self.fetchCertificate(for: team, completionHandler: completionHandler)
                        }
                        catch
                        {
                            completionHandler(.failure(error))
                        }
                    }
                }
                else
                {
                    ALTAppleAPI.shared.addCertificate(machineName: "AltStore", to: team) { (certificate, error) in
                        do
                        {
                            let certificate = try Result(certificate, error).get()
                            guard let privateKey = certificate.privateKey else { throw InstallError.missingPrivateKey }
                            
                            ALTAppleAPI.shared.fetchCertificates(for: team) { (certificates, error) in
                                do
                                {
                                    let certificates = try Result(certificates, error).get()
                                    
                                    guard let certificate = certificates.first(where: { $0.serialNumber == certificate.serialNumber }) else {
                                        throw InstallError.missingCertificate
                                    }
                                    
                                    certificate.privateKey = privateKey
                                    
                                    completionHandler(.success(certificate))
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
    
    func registerAppID(name appName: String, identifier: String, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let bundleID = "com.\(team.identifier).\(identifier)"
        
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
    
    func updateFeatures(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, completionHandler: @escaping (Result<ALTAppID, Error>) -> Void)
    {
        let requiredFeatures = app.entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = app.entitlements[.appGroups] as? [String], !applicationGroups.isEmpty
        {
            features[.appGroups] = true
        }
        
        let appID = appID.copy() as! ALTAppID
        appID.features = features
        
        ALTAppleAPI.shared.update(appID, team: team) { (appID, error) in
            completionHandler(Result(appID, error))
        }
    }
    
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
    
    func fetchProvisioningProfile(for appID: ALTAppID, team: ALTTeam, completionHandler: @escaping (Result<ALTProvisioningProfile, Error>) -> Void)
    {
        ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, team: team) { (profile, error) in
            completionHandler(Result(profile, error))
        }
    }
    
    func install(_ application: ALTApplication, to device: ALTDevice, team: ALTTeam, appID: ALTAppID, certificate: ALTCertificate, profile: ALTProvisioningProfile, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        DispatchQueue.global().async {
            do
            {
                let infoPlistURL = application.fileURL.appendingPathComponent("Info.plist")
                
                guard var infoDictionary = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] else { throw ALTError(.missingInfoPlist) }
                infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
                infoDictionary[Bundle.Info.deviceID] = device.identifier
                try (infoDictionary as NSDictionary).write(to: infoPlistURL)
                
                let resigner = ALTSigner(team: team, certificate: certificate)
                resigner.signApp(at: application.fileURL, provisioningProfiles: [profile]) { (success, error) in
                    do
                    {
                        try Result(success, error).get()
                        
                        ALTDeviceManager.shared.installApp(at: application.fileURL, toDeviceWithUDID: device.identifier) { (success, error) in
                            completionHandler(Result(success, error))
                        }
                    }
                    catch
                    {
                        print("Failed to install app", error)
                        completionHandler(.failure(error))
                    }
                }
            }
            catch
            {
                print("Failed to install AltStore", error)
                completionHandler(.failure(error))
            }
        }
    }
}
