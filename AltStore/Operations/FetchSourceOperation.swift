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

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    let managedObjectContext: NSManagedObjectContext
    
    // When updating an existing source.
    @Managed
    private(set) var source: Source?
    
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
    
    private init(sourceURL: URL, source: Source?, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.sourceURL = sourceURL
        self.managedObjectContext = managedObjectContext
        self.source = source
        
        //TODO: Respect some caching
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
                    let (data, response) = try Result((data, response), error).get()
                    
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
                    decoder.sourceContext = Source.DecodingContext()
                    
                    let source = try decoder.decode(Source.self, from: data)
                    let identifier = source.identifier
                    
                    try self.verify(source, response: response)
                    
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
    func verify(_ source: Source, response: URLResponse) throws
    {
        if let blockedSourceIDs = UserDefaults.shared.blockedSourceIDs
        {
            guard !blockedSourceIDs.contains(source.identifier) else { throw SourceError.blocked(source) }
        }
        
        if let blockedSourceURLs = UserDefaults.shared.blockedSourceURLs
        {
            guard !blockedSourceURLs.contains(source.sourceURL) else { throw SourceError.blocked(source) }
            
            if let responseURL = response.url
            {
                // responseURL may differ from sourceURL (e.g. due to redirects), so double-check it's also not blocked.
                guard !blockedSourceURLs.contains(responseURL) else { throw SourceError.blocked(source) }
            }
        }
        
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
        
        //TODO: Verify no duplicate permissions? (Or implicitly merge them probs)
        
        if let previousSourceID = self.$source.identifier
        {
            guard source.identifier == previousSourceID else { throw SourceError.changedID(source.identifier, previousID: previousSourceID, for: source) }
        }
    }
}
