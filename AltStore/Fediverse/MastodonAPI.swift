//
//  MastodonAPI.swift
//  AltStore
//
//  Created by Riley Testut on 7/24/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore

extension MastodonAPI
{
    #if SANDBOX
    static let instanceURL = URL(string: "https://fedi.alt.store")!
    #else
    static let instanceURL = URL(string: "https://explore.alt.store")!
    #endif
}

fileprivate extension MastodonAPI
{
    struct ConversationContext: Decodable
    {
        var ancestors: [Toot]
        var descendants: [Toot]
    }
}

struct MastodonError: ALTLocalizedError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = MastodonError
        
        case unknown
        case unauthorized
        case http
    }
    
    static func unknown(file: String = #fileID, line: UInt = #line) -> MastodonError { MastodonError(code: .unknown, sourceFile: file, sourceLine: line) }
    static func unauthorized(file: String = #fileID, line: UInt = #line) -> MastodonError { MastodonError(code: .unauthorized, sourceFile: file, sourceLine: line) }
    static func http(statusCode: Int, file: String = #fileID, line: UInt = #line) -> MastodonError { MastodonError(code: .http, statusCode: statusCode, sourceFile: file, sourceLine: line) }
    
    let code: Code
    
    var statusCode: Int?
    
    var errorFailure: String?
    var errorTitle: String?
    
    var sourceFile: String?
    var sourceLine: UInt?
        
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown: return String(localized: "An unknown error occured.")
        case .unauthorized: return String(localized: "This request requires an authenticated user.")
        case .http:
            guard let statusCode else { return String(localized: "An HTTP error occured.") }
            return String(localized: "HTTP Status Code: \(statusCode)") //TODO: Does escaping variables work in localized strings?
        }
    }
}

final class MastodonAPI
{
    static let shared = MastodonAPI()
         
    private init()
    {
    }
}

extension MastodonAPI
{
    func fetchToots(ids: Set<String>) async throws -> [Toot]
    {
        // TODO: Handle rate limits
        
        let fetchLimit = 100
        var fetchedToots: [Toot] = []
        
        var statusIDs = Array(ids)
        while !statusIDs.isEmpty
        {
            let statuses = statusIDs.prefix(fetchLimit)
            statusIDs.removeFirst(statuses.count)
            
            let toots = try await self._fetchToots(ids: Set(statuses))
            fetchedToots += toots
        }
        
        return fetchedToots
    }
    
    private func _fetchToots(ids: Set<String>) async throws -> [Toot]
    {
        // TODO: Handle rate limits
        
        let fetchLimit = 100
        
        guard !ids.isEmpty else { return [] }
        
        var endpoint = MastodonAPI.instanceURL.appendingPathComponent("api/v1/statuses").absoluteString + "?limit=\(fetchLimit)"
        for id in ids
        {
            endpoint += "&id[]=\(id)"
        }
        
        guard let requestURL = URL(string: endpoint) else { throw MastodonError.unknown() }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse
        {
            switch httpResponse.statusCode
            {
            case 200...299: break
            case 401: throw MastodonError.unauthorized()
            default: throw MastodonError.http(statusCode: httpResponse.statusCode)
            }
        }
        
        let decoder = Foundation.JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let toots = try decoder.decode([Toot].self, from: data)
        return toots
    }
}

extension MastodonAPI
{
    func fetchFavorites(tootID: Int, limit: Int? = 20) async throws -> [Account]
    {
        // TODO: Handle rate/fetch limits
        
        var endpoint = MastodonAPI.instanceURL.appendingPathComponent("api/v1/statuses/\(tootID)/favourited_by").absoluteString
        if let limit
        {
            endpoint += "?limit=\(limit)"
        }
        
        guard let requestURL = URL(string: endpoint) else { throw MastodonError.unknown() }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse
        {
            switch httpResponse.statusCode
            {
            case 200...299: break
            case 401: throw MastodonError.unauthorized()
            default: throw MastodonError.http(statusCode: httpResponse.statusCode)
            }
        }
        
        let decoder = Foundation.JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let accounts = try decoder.decode([Account].self, from: data)
        return accounts
    }
}
