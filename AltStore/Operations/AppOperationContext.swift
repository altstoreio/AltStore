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

class AppOperationContext
{
    var appIdentifier: String
    var group: OperationGroup
        
    var installedApp: InstalledApp? {
        didSet {
            self.installedAppContext = self.installedApp?.managedObjectContext
        }
    }
    private var installedAppContext: NSManagedObjectContext?
    
    var resignedFileURL: URL?
    var connection: NWConnection?
    
    var error: Error? {
        get {
            return _error ?? self.group.error
        }
        set {
            _error = newValue
        }
    }
    private var _error: Error?
    
    init(appIdentifier: String, group: OperationGroup)
    {
        self.appIdentifier = appIdentifier
        self.group = group
    }
}
