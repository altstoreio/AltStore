//
//  AnisetteServer.swift
//  AltStore
//
//  Created by Caroline Moore on 5/26/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

struct AnisetteServer: Decodable
{
    var name: String
    var url: URL
}

extension AnisetteServer: Identifiable
{
    var id: URL { self.url }
}

private extension AnisetteServer
{
    var dictionaryRepresentation: [String: Any] {
        [
            CodingKeys.name.stringValue: self.name,
            CodingKeys.url.stringValue: self.url.absoluteString
        ]
    }

    init?(dictionary: [String: Any])
    {
        guard let name = dictionary[CodingKeys.name.stringValue] as? String,
              let urlString = dictionary[CodingKeys.url.stringValue] as? String,
              let url = URL(string: urlString)
        else { return nil }

        self.name = name
        self.url = url
    }
}

extension UserDefaults
{
    @nonobjc var anisetteServers: [AnisetteServer]? {
        get {
            guard let servers = _anisetteServers?.compactMap({ AnisetteServer(dictionary: $0) }) else { return nil }
            return servers
        }
        set {
            _anisetteServers = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    @NSManaged @objc(anisetteServers) private var _anisetteServers: [[String: Any]]?
}

extension AnisetteServer
{
    /// The client identity AltStore presents to Apple in place of the one an anisette server
    /// reports, so sign-in does not depend on the identity each server chooses.
    static let clientInfo = "<Mac15,7> <macOS;27.0;26A5378j> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"

    static let userAgent = "akd/1.0 CFNetwork/808.1.4"
}
