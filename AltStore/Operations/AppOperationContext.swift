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

import AltSign

class OperationContext
{
    var server: Server?
    var error: Error?
}

class AuthenticatedOperationContext: OperationContext
{
    var session: ALTAppleAPISession?
    
    var team: ALTTeam?
    var certificate: ALTCertificate?
}

@dynamicMemberLookup
class AppOperationContext
{
    let bundleIdentifier: String
    private let authenticatedContext: AuthenticatedOperationContext
    
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
    var resignedApp: ALTApplication?
    var installationConnection: ServerConnection?
    
    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        
        do { try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil) }
        catch { self.error = error }
        
        return temporaryDirectory
    }()
}
