//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import Roxas

enum VerificationError: ALTLocalizedError
{
    case privateEntitlements(ALTApplication, entitlements: [String: Any])
    case mismatchedBundleIdentifiers(ALTApplication, sourceBundleID: String)
    
    var app: ALTApplication {
        switch self
        {
        case .privateEntitlements(let app, _): return app
        case .mismatchedBundleIdentifiers(let app, _): return app
        }
    }
    
    var errorFailure: String? {
        return String(format: NSLocalizedString("“%@” could not be installed.", comment: ""), app.name)
    }
    
    var failureReason: String? {
        switch self
        {
        case .privateEntitlements(let app, _):
            return String(format: NSLocalizedString("“%@” requires private permissions.", comment: ""), app.name)
            
        case .mismatchedBundleIdentifiers(let app, let sourceBundleID):
            return String(format: NSLocalizedString("The bundle ID “%@” does not match the one specified by the source (“%@”).", comment: ""), app.bundleIdentifier, sourceBundleID)
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
            
            guard let app = self.context.app else { throw OperationError.invalidParameters }
            
            guard app.bundleIdentifier == self.context.bundleIdentifier else {
                throw VerificationError.mismatchedBundleIdentifiers(app, sourceBundleID: self.context.bundleIdentifier)
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
                    let error = VerificationError.privateEntitlements(app, entitlements: entitlements)
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
            switch error
            {
            case .privateEntitlements(_, let entitlements):
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
                
            case .mismatchedBundleIdentifiers: return completion(.failure(error))
            }
        }
    }
}
