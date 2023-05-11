//
//  FetchKnownSourcesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

private extension URL
{
    #if STAGING
    static let sources = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/altstore/sources.json")!
    #else
    static let sources = URL(string: "https://cdn.altstore.io/file/altstore/altstore/sources.json")!
    #endif
}

extension FetchKnownSourcesOperation
{
    struct Source: Decodable
    {
        var identifier: String
        var sourceURL: URL?
    }
    
    private struct Response: Decodable
    {
        var version: Int
        
        var trusted: [Source]
        var blocked: [Source]?
    }
}

class FetchKnownSourcesOperation: ResultOperation<([FetchKnownSourcesOperation.Source], [FetchKnownSourcesOperation.Source])>
{
    private let session: URLSession
    
    override init()
    {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
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
                let sources = (trusted: response.trusted, blocked: response.blocked ?? [])
                
                // Cache trusted sources
                UserDefaults.shared.trustedSourceIDs = Set(sources.trusted.map { $0.identifier })
                
                // Cache blocked sources
                UserDefaults.shared.blockedSourceIDs = Set(sources.blocked.map { $0.identifier })
                UserDefaults.shared.blockedSourceURLs = Set(sources.blocked.compactMap { $0.sourceURL })
                
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
