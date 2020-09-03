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
                    
                    if identifier == Source.altStoreIdentifier, let patreonAccessToken = source.userInfo?[.patreonAccessToken]
                    {
                        Keychain.shared.patreonCreatorAccessToken = patreonAccessToken
                    }
                    
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
