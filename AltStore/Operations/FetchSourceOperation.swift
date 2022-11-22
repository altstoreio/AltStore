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
    }
    
    static func unsupported(_ source: Source) -> SourceError { SourceError(code: .unsupported, source: source) }
    static func duplicateBundleID(_ bundleID: String, source: Source) -> SourceError { SourceError(code: .duplicateBundleID, source: source, duplicateBundleID: bundleID) }
}

struct SourceError: ALTLocalizedError
{
    var code: Code
    var errorTitle: String?
    var errorFailure: String?
    
    @Managed var source: Source
    var duplicateBundleID: String?
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unsupported: return String(format: NSLocalizedString("The source “%@” is not supported by this version of AltStore.", comment: ""), self.$source.name)
        case .duplicateBundleID:
            let bundleIDFragment = self.duplicateBundleID.map { String(format: NSLocalizedString("the bundle identifier %@", comment: ""), $0) } ?? NSLocalizedString("the same bundle identifier", comment: "")
            let failureReason = String(format: NSLocalizedString("The source “%@” contains multiple apps with %@.", comment: ""), self.$source.name, bundleIDFragment)
            return failureReason
        }
    }
}

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    let managedObjectContext: NSManagedObjectContext
    
    private let session: URLSession
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter
    }()
    
    init(sourceURL: URL, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.sourceURL = sourceURL
        self.managedObjectContext = managedObjectContext
        
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
        }
    }
}
