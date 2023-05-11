//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore
import Roxas

extension SourceError
{
    enum Code: Int, ALTErrorCode
    {
        typealias Error = SourceError
        
        case unsupported
        case duplicateBundleID
        case duplicateVersion
        
        case changedID
        case duplicate
    }
    
    static func unsupported(_ source: Source) -> SourceError { SourceError(code: .unsupported, source: source) }
    static func duplicateBundleID(_ bundleID: String, source: Source) -> SourceError { SourceError(code: .duplicateBundleID, source: source, bundleID: bundleID) }
    static func duplicateVersion(_ version: String, for app: StoreApp, source: Source) -> SourceError { SourceError(code: .duplicateVersion, source: source, app: app, version: version) }
    
    static func changedID(_ identifier: String, previousID: String, source: Source) -> SourceError { SourceError(code: .changedID, source: source, sourceID: identifier, previousSourceID: previousID) }
    static func duplicate(_ source: Source, previousSourceName: String?) -> SourceError { SourceError(code: .duplicate, source: source, previousSourceName: previousSourceName) }
}

struct SourceError: ALTLocalizedError
{
    let code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var source: Source
    @Managed var app: StoreApp?
    var bundleID: String?
    var version: String?
    
    @UserInfoValue var previousSourceName: String?
    
    // Store in userInfo so they can be viewed from Error Log.
    @UserInfoValue var sourceID: String?
    @UserInfoValue var previousSourceID: String?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unsupported: return String(format: NSLocalizedString("The source “%@” is not supported by this version of AltStore.", comment: ""), self.$source.name)
        case .duplicateBundleID:
            let bundleIDFragment = self.bundleID.map { String(format: NSLocalizedString("the bundle identifier %@", comment: ""), $0) } ?? NSLocalizedString("the same bundle identifier", comment: "")
            let failureReason = String(format: NSLocalizedString("The source “%@” contains multiple apps with %@.", comment: ""), self.$source.name, bundleIDFragment)
            return failureReason
            
        case .duplicateVersion:
            var versionFragment = NSLocalizedString("duplicate versions", comment: "")
            if let version
            {
                versionFragment += " (\(version))"
            }
            
            let appFragment: String
            if let name = self.$app.name, let bundleID = self.$app.bundleIdentifier
            {
                appFragment = name + " (\(bundleID))"
            }
            else
            {
                appFragment = NSLocalizedString("one or more apps", comment: "")
            }
                        
            let failureReason = String(format: NSLocalizedString("The source “%@” contains %@ for %@.", comment: ""), self.$source.name, versionFragment, appFragment)
            return failureReason
            
        case .changedID:
            let failureReason = String(format: NSLocalizedString("The identifier of the source “%@” has changed.", comment: ""), self.$source.name)
            return failureReason
            
        case .duplicate:
            let baseMessage = String(format: NSLocalizedString("A source with the identifier '%@' already exists", comment: ""), self.$source.identifier)
            guard let previousSourceName else { return baseMessage + "." }
            
            let failureReason = baseMessage + " (“\(previousSourceName)”)."
            return failureReason
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .changedID: return NSLocalizedString("A source cannot change its identifier once added. This source can no longer be updated.", comment: "")
        case .duplicate:
            let failureReason = NSLocalizedString("Please remove the existing source in order to add this one.", comment: "")
            return failureReason
            
        default: return nil
        }
    }
}

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    let managedObjectContext: NSManagedObjectContext
    
    // Non-nil when updating an existing source.
    @Managed
    private var source: Source?
    
    private let session: URLSession
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter
    }()
    
    // New source
    convenience init(sourceURL: URL, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.init(sourceURL: sourceURL, source: nil, managedObjectContext: managedObjectContext)
    }
    
    // Existing source
    convenience init(source: Source, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.init(sourceURL: source.sourceURL, source: source, managedObjectContext: managedObjectContext)
    }
    
    private init(sourceURL: URL, source: Source?, managedObjectContext: NSManagedObjectContext)
    {
        self.sourceURL = sourceURL
        self.managedObjectContext = managedObjectContext
        self.source = source
        
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        self.session = URLSession(configuration: configuration)
    }
    
    override func main()
    {
        super.main()
        
        let dataTask = self.session.dataTask(with: self.sourceURL) { (data, response, error) in
            
            let childContext = DatabaseManager.shared.persistentContainer.newBackgroundContext(withParent: self.managedObjectContext)
            childContext.mergePolicy = NSOverwriteMergePolicy
            childContext.perform {
                do
                {
                    let (data, _) = try Result((data, response), error).get()
                    
                    let decoder = AltStoreCore.JSONDecoder()
                    decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
                        let container = try decoder.singleValueContainer()
                        let text = try container.decode(String.self)
                        
                        // Full ISO8601 Format.
                        self.dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
                        if let date = self.dateFormatter.date(from: text)
                        {
                            return date
                        }
                        
                        // Just date portion of ISO8601.
                        self.dateFormatter.formatOptions = [.withFullDate]
                        if let date = self.dateFormatter.date(from: text)
                        {
                            return date
                        }
                        
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date is in invalid format.")
                    })
                    
                    decoder.managedObjectContext = childContext
                    decoder.sourceURL = self.sourceURL
                    
                    let source = try decoder.decode(Source.self, from: data)
                    let identifier = source.identifier
                    
                    try self.verify(source)
                    
                    try childContext.save()
                    
                    self.managedObjectContext.perform {
                        if let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), identifier), in: self.managedObjectContext)
                        {
                            self.finish(.success(source))
                        }
                        else
                        {
                            self.finish(.failure(OperationError.noSources))
                        }
                    }
                }
                catch
                {
                    self.managedObjectContext.perform {
                        self.finish(.failure(error))
                    }
                }
            }
        }
        
        self.progress.addChild(dataTask.progress, withPendingUnitCount: 1)
        
        dataTask.resume()
    }
}

private extension FetchSourceOperation
{
    func verify(_ source: Source) throws
    {
        #if !BETA
        if let trustedSourceIDs = UserDefaults.shared.trustedSourceIDs
        {
            guard trustedSourceIDs.contains(source.identifier) || source.identifier == Source.altStoreIdentifier else { throw SourceError(code: .unsupported, source: source) }
        }
        #endif
        
        var bundleIDs = Set<String>()
        for app in source.apps
        {
            guard !bundleIDs.contains(app.bundleIdentifier) else { throw SourceError.duplicateBundleID(app.bundleIdentifier, source: source) }
            bundleIDs.insert(app.bundleIdentifier)

            var versions = Set<String>()
            for version in app.versions
            {
                guard !versions.contains(version.version) else { throw SourceError.duplicateVersion(version.version, for: app, source: source) }
                versions.insert(version.version)
            }
        }
        
        if let previousSourceID = self.$source.identifier
        {
            guard source.identifier == previousSourceID else { throw SourceError.changedID(source.identifier, previousID: previousSourceID, source: source) }
        }
    }
}
