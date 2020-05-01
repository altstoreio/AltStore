//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

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
            self.managedObjectContext.perform {
                do
                {
                    let (data, _) = try Result((data, response), error).get()
                    
                    let decoder = JSONDecoder()
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
                    
                    decoder.managedObjectContext = self.managedObjectContext
                    decoder.sourceURL = self.sourceURL
                    
                    let source = try decoder.decode(Source.self, from: data)
                    
                    if source.identifier == Source.altStoreIdentifier, let patreonAccessToken = source.userInfo?[.patreonAccessToken]
                    {
                        Keychain.shared.patreonCreatorAccessToken = patreonAccessToken
                    }
                    
                    self.finish(.success(source))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
        
        self.progress.addChild(dataTask.progress, withPendingUnitCount: 1)
        
        dataTask.resume()
    }
}
