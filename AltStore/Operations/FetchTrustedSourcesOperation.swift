//
//  FetchTrustedSourcesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

private extension URL
{
    #if STAGING
    static let trustedSources = URL(string: "https://raw.githubusercontent.com/SideStore/SideStore/develop/trustedapps.json")!
    #else
    static let trustedSources = URL(string: "https://raw.githubusercontent.com/SideStore/SideStore/develop/trustedapps.json")!
    #endif
}

extension FetchTrustedSourcesOperation
{
    struct TrustedSource: Decodable
    {
        var identifier: String
        var sourceURL: URL?
    }
    
    private struct Response: Decodable
    {
        var version: Int
        var sources: [FetchTrustedSourcesOperation.TrustedSource]
    }
}

final class FetchTrustedSourcesOperation: ResultOperation<[FetchTrustedSourcesOperation.TrustedSource]>
{
    override func main()
    {
        super.main()
        
        let dataTask = URLSession.shared.dataTask(with: .trustedSources) { (data, response, error) in
            do
            {
                if let response = response as? HTTPURLResponse
                {
                    guard response.statusCode != 404 else {
                        self.finish(.failure(URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: URL.trustedSources])))
                        return
                    }
                }
                
                guard let data = data else { throw error! }
                
                let response = try Foundation.JSONDecoder().decode(Response.self, from: data)
                self.finish(.success(response.sources))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
        
        dataTask.resume()
    }
}
