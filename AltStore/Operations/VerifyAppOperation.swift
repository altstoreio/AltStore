//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = VerificationError
        
        case privateEntitlements
        case mismatchedBundleIdentifiers
        case iOSVersionNotSupported
    }
    
    static func privateEntitlements(_ entitlements: [String: Any], app: ALTApplication) -> VerificationError { VerificationError(code: .privateEntitlements, app: app, entitlements: entitlements) }
    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError  { VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID) }
    
    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app, deviceOSVersion: osVersion, requiredOSVersion: requiredOSVersion)
    }
}

struct VerificationError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var app: AppProtocol?
    var entitlements: [String: Any]?
    var sourceBundleID: String?
    var deviceOSVersion: OperatingSystemVersion?
    var requiredOSVersion: OperatingSystemVersion?
    
    var errorDescription: String? {
        //TODO: Make this automatic somehow with ALTLocalizedError
        guard self.errorFailure == nil else { return nil }
        
        switch self.code
        {
        case .iOSVersionNotSupported:
            guard let deviceOSVersion else { break }
            
            var failureReason = self.errorFailureReason
            if self.app == nil
            {
                // failureReason does not start with app name, so make first letter lowercase.
                let firstLetter = failureReason.prefix(1).lowercased()
                failureReason = firstLetter + failureReason.dropFirst()
            }
            
            let localizedDescription = String(format: NSLocalizedString("This device is running iOS %@, but %@", comment: ""), deviceOSVersion.stringValue, failureReason)
            return localizedDescription
            
        default: break
        }
        
        return self.errorFailureReason
    }
    
    var errorFailureReason: String {
        switch self.code
        {
        case .privateEntitlements:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ requires private permissions.", comment: ""), appName)
            
        case .mismatchedBundleIdentifiers:
            if let appBundleID = self.$app.bundleIdentifier, let bundleID = self.sourceBundleID
            {
                return String(format: NSLocalizedString("The bundle ID “%@” does not match the one specified by the source (“%@”).", comment: ""), appBundleID, bundleID)
            }
            else
            {
                return NSLocalizedString("The bundle ID does not match the one specified by the source.", comment: "")
            }
            
        case .iOSVersionNotSupported:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            let deviceOSVersion = self.deviceOSVersion ?? ProcessInfo.processInfo.operatingSystemVersion
            
            guard let requiredOSVersion else {
                return String(format: NSLocalizedString("%@ does not support iOS %@.", comment: ""), appName, deviceOSVersion.stringValue)
            }
            
            if deviceOSVersion > requiredOSVersion
            {
                // Device OS version is higher than maximum supported OS version.
                
                let failureReason = String(format: NSLocalizedString("%@ requires iOS %@ or earlier.", comment: ""), appName, requiredOSVersion.stringValue)
                return failureReason
            }
            else
            {
                // Device OS version is lower than minimum supported OS version.
                
                let failureReason = String(format: NSLocalizedString("%@ requires iOS %@ or later.", comment: ""), appName, requiredOSVersion.stringValue)
                return failureReason
            }
        }
    }
}

@objc(VerifyAppOperation)
class VerifyAppOperation: ResultOperation<Void>
{
    let context: AppOperationContext
    var verificationHandler: ((VerificationError) -> Bool)?
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
            self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)
            
            guard let app = self.context.app else { throw OperationError.invalidParameters }
            
            guard app.bundleIdentifier == self.context.bundleIdentifier else {
                throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            if #available(iOS 13.5, *)
            {
                // No psychic paper, so we can ignore private entitlements
                app.hasPrivateEntitlements = false
            }
            else
            {
                // Make sure this goes last, since once user responds to alert we don't do any more app verification.
                if let commentStart = app.entitlementsString.range(of: "<!---><!-->"), let commentEnd = app.entitlementsString.range(of: "<!-- -->")
                {
                    // Psychic Paper private entitlements.
                    
                    let entitlementsStart = app.entitlementsString.index(after: commentStart.upperBound)
                    let rawEntitlements = String(app.entitlementsString[entitlementsStart ..< commentEnd.lowerBound])
                    
                    let plistTemplate = """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                        <plist version="1.0">
                            <dict>
                            %@
                            </dict>
                        </plist>
                        """
                    let entitlementsPlist = String(format: plistTemplate, rawEntitlements)
                    let entitlements = try PropertyListSerialization.propertyList(from: entitlementsPlist.data(using: .utf8)!, options: [], format: nil) as! [String: Any]
                    
                    app.hasPrivateEntitlements = true
                    let error = VerificationError.privateEntitlements(entitlements, app: app)
                    self.process(error) { (result) in
                        self.finish(result.mapError { $0 as Error })
                    }
                    
                    return
                }
                else
                {
                    app.hasPrivateEntitlements = false
                }
            }
            
            self.finish(.success(()))
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}

private extension VerifyAppOperation
{
    func process(_ error: VerificationError, completion: @escaping (Result<Void, VerificationError>) -> Void)
    {
        guard let presentingViewController = self.context.presentingViewController else { return completion(.failure(error)) }
        
        DispatchQueue.main.async {
            switch error.code
            {
            case .privateEntitlements:
                guard let entitlements = error.entitlements else { return completion(.failure(error)) }
                let permissions = entitlements.keys.sorted().joined(separator: "\n")
                let message = String(format: NSLocalizedString("""
                    You must allow access to these private permissions before continuing:
                    
                    %@
                    
                    Private permissions allow apps to do more than normally allowed by iOS, including potentially accessing sensitive private data. Make sure to only install apps from sources you trust.
                    """, comment: ""), permissions)
                
                let alertController = UIAlertController(title: error.failureReason ?? error.localizedDescription, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Allow Access", comment: ""), style: .destructive) { (action) in
                    completion(.success(()))
                })
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Deny Access", comment: ""), style: .default, handler: { (action) in
                    completion(.failure(error))
                }))
                presentingViewController.present(alertController, animated: true, completion: nil)
                
            case .mismatchedBundleIdentifiers, .iOSVersionNotSupported: return completion(.failure(error))
            }
        }
    }
}
