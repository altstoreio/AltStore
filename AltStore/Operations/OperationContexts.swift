//
//  Contexts.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import Network

import AltStoreCore
import AltSign

class OperationContext
{
    var server: Server?
    var error: Error?
    
    var presentingViewController: UIViewController?
    
    let operations: NSHashTable<Foundation.Operation>
    
    init(server: Server? = nil, error: Error? = nil, operations: [Foundation.Operation] = [])
    {
        self.server = server
        self.error = error
        
        self.operations = NSHashTable<Foundation.Operation>.weakObjects()
        for operation in operations
        {
            self.operations.add(operation)
        }
    }
    
    convenience init(context: OperationContext)
    {
        self.init(server: context.server, error: context.error, operations: context.operations.allObjects)
    }
}

class AuthenticatedOperationContext: OperationContext
{
    var session: ALTAppleAPISession?
    
    var team: ALTTeam?
    var certificate: ALTCertificate?
    
    weak var authenticationOperation: AuthenticationOperation?
    
    convenience init(context: AuthenticatedOperationContext)
    {
        self.init(server: context.server, error: context.error, operations: context.operations.allObjects)
        
        self.session = context.session
        self.team = context.team
        self.certificate = context.certificate
        self.authenticationOperation = context.authenticationOperation
    }
}

@dynamicMemberLookup
class AppOperationContext
{
    let bundleIdentifier: String
    let authenticatedContext: AuthenticatedOperationContext
    
    var app: ALTApplication?
    var provisioningProfiles: [String: ALTProvisioningProfile]?
    
    var isFinished = false
    
    var error: Error? {
        get {
            return _error ?? self.authenticatedContext.error
        }
        set {
            _error = newValue
        }
    }
    private var _error: Error?
    
    init(bundleIdentifier: String, authenticatedContext: AuthenticatedOperationContext)
    {
        self.bundleIdentifier = bundleIdentifier
        self.authenticatedContext = authenticatedContext
    }
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<AuthenticatedOperationContext, T>) -> T
    {
        return self.authenticatedContext[keyPath: keyPath]
    }
}

class InstallAppOperationContext: AppOperationContext
{
    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        
        do { try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil) }
        catch { self.error = error }
        
        return temporaryDirectory
    }()
    
    var resignedApp: ALTApplication?
    var installationConnection: ServerConnection?
    var installedApp: InstalledApp? {
        didSet {
            self.installedAppContext = self.installedApp?.managedObjectContext
        }
    }
    private var installedAppContext: NSManagedObjectContext?
    
    var beginInstallationHandler: ((InstalledApp) -> Void)?
    
    var alternateIconURL: URL?
}
