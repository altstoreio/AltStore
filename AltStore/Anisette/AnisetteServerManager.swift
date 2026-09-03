//
//  AnisetteServerManager.swift
//  AltStore
//
//  Created by Caroline Moore on 6/19/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

private extension URL
{
    static let anisetteServers = URL(string: "https://cdn.altstore.io/file/altstore/altstore/anisette-servers.json")!
}

class AnisetteServerManager
{
    static let shared = AnisetteServerManager()

    private let session: URLSession

    private init()
    {
        let configuration = URLSessionConfiguration.default

        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }

        self.session = URLSession(configuration: configuration)
    }

    func fetchServers() async throws -> [AnisetteServer]
    {
        struct Response: Decodable
        {
            var servers: [AnisetteServer]
        }

        let (data, _) = try await self.session.data(from: .anisetteServers)
        let response = try Foundation.JSONDecoder().decode(Response.self, from: data)

        UserDefaults.standard.anisetteServers = response.servers

        return response.servers
    }

    // Verifies a URL points to a working anisette server.
    func validate(_ url: URL) async throws
    {
        let clientInfoURL = url.appending(components: "v3", "client_info")

        var request = URLRequest(url: clientInfoURL)
        request.timeoutInterval = 30

        let (data, urlResponse) = try await self.session.data(for: request)

        if let urlResponse = urlResponse as? HTTPURLResponse
        {
            // URL points at something that isn't an anisette server.
            if urlResponse.statusCode == 404
            {
                throw AnisetteServerError.invalidServer()
            }

            // Server is reachable but erroring (e.g. 502/522 when its backend is down).
            guard urlResponse.statusCode == 200 else
            {
                Logger.sideload.error("Anisette server \(clientInfoURL, privacy: .public) returned status \(urlResponse.statusCode).")
                throw AnisetteServerError.unavailable(serverURL: url, debugDescription: "The server returned HTTP error code \(urlResponse.statusCode).")
            }
        }

        struct Response: Decodable
        {
            var clientInfo: String
            var userAgent: String
        }

        let decoder = Foundation.JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do
        {
            _ = try decoder.decode(Response.self, from: data)
        }
        catch
        {
            // Responded with 200, but the body isn't valid anisette client_info.
            throw AnisetteServerError.invalidServer()
        }
    }
}
