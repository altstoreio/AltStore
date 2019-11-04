//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>
{
    let sourceURL: URL
    
    private let session: URLSession
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter
    }()
    
    init(sourceURL: URL)
    {
        self.sourceURL = sourceURL
        
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        self.session = URLSession(configuration: configuration)
    }
    
    override func main()
    {
        super.main()
        
        let dataTask = self.session.dataTask(with: self.sourceURL) { (data, response, error) in
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
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
                    
                    decoder.managedObjectContext = context
                    
                    let source = try decoder.decode(Source.self, from: data)
                    
                    if let patreonAccessToken = source.userInfo?[.patreonAccessToken]
                    {
                        Keychain.shared.patreonCreatorAccessToken = patreonAccessToken
                    }
                    
                    #if STAGING
                    source.sourceURL = self.sourceURL
                    #endif
                    
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
