//
//  URL+Normalized.swift
//  AltStoreCore
//
//  Created by Riley Testut on 11/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

public extension URL
{
    func normalized() throws -> String
    {
        // Based on https://encyclopedia.pub/entry/29841

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { throw URLError(.badURL, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
        
        if components.scheme == nil && components.host == nil
        {
            // Special handling for URLs without explicit scheme & incorrectly assumed to have nil host (e.g. "altstore.io/my/path")
            guard let updatedComponents = URLComponents(string: "https://" + self.absoluteString) else { throw URLError(.cannotFindHost, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
            components = updatedComponents
        }
        
        // 1. Don't use percent encoding
        guard let host = components.host else { throw URLError(.cannotFindHost, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
        
        // 2. Ignore scheme
        var normalizedURL = host
        
        // 3. Add port (if not default)
        if let port = components.port, port != 80 && port != 443
        {
            normalizedURL += ":" + String(port)
        }
        
        // 4. Add path without fragment or query parameters
        // 5. Remove duplicate slashes
        let path = components.path.replacingOccurrences(of: "//", with: "/") // Only remove duplicate slashes from path, not entire URL.
        normalizedURL += path // path has leading `/`
                
        // 6. Convert to lowercase
        normalizedURL = normalizedURL.lowercased()
        
        // 7. Remove trailing `/`
        if normalizedURL.hasSuffix("/")
        {
            normalizedURL.removeLast()
        }
        
        // 8. Remove leading "www"
        if normalizedURL.hasPrefix("www.")
        {
            normalizedURL.removeFirst(4)
        }
        
        return normalizedURL
    }
}
