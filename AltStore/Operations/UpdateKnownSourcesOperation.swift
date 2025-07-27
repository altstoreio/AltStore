//
//  UpdateKnownSourcesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

private extension URL
{
    #if MARKETPLACE
    
    #if STAGING
    static let sources = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore/marketplace-sources.json")!
    #else
    static let sources = URL(string: "https://cdn.altstore.io/file/altstore/altstore/marketplace-sources.json")!
    #endif
    
    #elseif STAGING
    static let sources = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore/sources.json")!
    #else
    static let sources = URL(string: "https://cdn.altstore.io/file/altstore/altstore/sources.json")!
    #endif
}

extension UpdateKnownSourcesOperation
{
    private struct Response: Decodable
    {
        var version: Int
        
        var trusted: [KnownSource]?
        var blocked: [KnownSource]?
    }
}

class UpdateKnownSourcesOperation: ResultOperation<([KnownSource], [KnownSource])>, @unchecked Sendable
{
    private let session: URLSession
    
    override init()
    {
        let configuration = URLSessionConfiguration.default
        
        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        
        self.session = URLSession(configuration: configuration)
    }
    
    override func main()
    {
        super.main()
        
        let dataTask = self.session.dataTask(with: .sources) { (data, response, error) in
            do
            {
                if let response = response as? HTTPURLResponse
                {
                    guard response.statusCode != 404 else {
                        self.finish(.failure(URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: URL.sources])))
                        return
                    }
                }
                
                guard let data = data else { throw error! }
                
                let response = try Foundation.JSONDecoder().decode(Response.self, from: data)
                let sources = (trusted: response.trusted ?? [], blocked: response.blocked ?? [])
                
                // Cache sources
                UserDefaults.shared.recommendedSources = sources.trusted
                UserDefaults.shared.blockedSources = sources.blocked
                
                self.finish(.success(sources))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
        
        dataTask.resume()
    }
}
