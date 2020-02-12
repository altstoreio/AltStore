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

class AppOperationContext
{
    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        
        do { try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil) }
        catch { self.error = error }
        
        return temporaryDirectory
    }()
    
    var bundleIdentifier: String
    var group: OperationGroup
    
    var app: ALTApplication?
    var resignedApp: ALTApplication?
    
    var installationConnection: ServerConnection?
    
    var installedApp: InstalledApp? {
        didSet {
            self.installedAppContext = self.installedApp?.managedObjectContext
        }
    }
    private var installedAppContext: NSManagedObjectContext?
    
    var isFinished = false
    
    var error: Error? {
        get {
            return _error ?? self.group.error
        }
        set {
            _error = newValue
        }
    }
    private var _error: Error?
    
    init(bundleIdentifier: String, group: OperationGroup)
    {
        self.bundleIdentifier = bundleIdentifier
        self.group = group
    }
}
