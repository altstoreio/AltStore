//
//  LoggedError.swift
//  AltStoreCore
//
//  Created by Riley Testut on 9/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

extension LoggedError
{
    public enum Operation: String
    {
        case install
        case update
        case refresh
        case activate
        case deactivate
        case backup
        case restore
        case enableJIT
    }
}

@objc(LoggedError)
public class LoggedError: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public private(set) var date: Date
    
    @nonobjc public var operation: Operation? {
        guard let rawOperation = self._operation else { return nil }
        
        let operation = Operation(rawValue: rawOperation)
        return operation
    }
    @NSManaged @objc(operation) private var _operation: String?
    
    @NSManaged public private(set) var domain: String
    @NSManaged public private(set) var code: Int32
    @NSManaged public private(set) var userInfo: [String: Any]
    
    @NSManaged public private(set) var appName: String
    @NSManaged public private(set) var appBundleID: String
    
    /* Relationships */
    @NSManaged public private(set) var storeApp: StoreApp?
    @NSManaged public private(set) var installedApp: InstalledApp?
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(error: Error, app: AppProtocol, date: Date = Date(), operation: Operation? = nil, context: NSManagedObjectContext)
    {
        super.init(entity: LoggedError.entity(), insertInto: context)
        
        self.date = date
        self._operation = operation?.rawValue
        
        let nsError: NSError
        if let error = error as? ALTServerError, error.code == .underlyingError, let underlyingError = error.underlyingError
        {
            nsError = underlyingError as NSError
        }
        else
        {
            nsError = error as NSError
        }
        
        self.domain = nsError.domain
        self.code = Int32(nsError.code)
        self.userInfo = nsError.userInfo
        
        self.appName = app.name
        self.appBundleID = app.bundleIdentifier
        
        switch app
        {
        case let storeApp as StoreApp: self.storeApp = storeApp
        case let installedApp as InstalledApp: self.installedApp = installedApp
        case let appVersion as AppVersion:
            if let installedApp = appVersion.app?.installedApp
            {
                self.installedApp = installedApp
            }
            else
            {
                self.storeApp = appVersion.app
            }
        
        default: break
        }
    }
}

public extension LoggedError
{
    var app: AppProtocol {
        // `as AppProtocol` needed to fix "cannot convert AnyApp to StoreApp" compiler error with Xcode 14.
        let app = self.installedApp ?? self.storeApp ?? AnyApp(name: self.appName, bundleIdentifier: self.appBundleID, url: nil, storeApp: nil) as AppProtocol
        return app
    }
    
    var error: NSError {
        let nsError = NSError(domain: self.domain, code: Int(self.code), userInfo: self.userInfo)
        return nsError
    }
    
    @objc
    var localizedDateString: String {
        let localizedDateString = LoggedError.dateFormatter.string(from: self.date)
        return localizedDateString
    }
    
    var localizedFailure: String? {
        guard let operation = self.operation else { return nil }
        switch operation
        {
        case .install: return String(format: NSLocalizedString("Install %@ Failed", comment: ""), self.appName)
        case .update: return String(format: NSLocalizedString("Update %@ Failed", comment: ""), self.appName)
        case .refresh: return String(format: NSLocalizedString("Refresh %@ Failed", comment: ""), self.appName)
        case .activate: return String(format: NSLocalizedString("Activate %@ Failed", comment: ""), self.appName)
        case .deactivate: return String(format: NSLocalizedString("Deactivate %@ Failed", comment: ""), self.appName)
        case .backup: return String(format: NSLocalizedString("Backup %@ Failed", comment: ""), self.appName)
        case .restore: return String(format: NSLocalizedString("Restore %@ Failed", comment: ""), self.appName)
        case .enableJIT: return String(format: NSLocalizedString("Enable JIT for %@ Failed", comment: ""), self.appName)
        }
    }
}

public extension LoggedError
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<LoggedError>
    {
        return NSFetchRequest<LoggedError>(entityName: "LoggedError")
    }
}
