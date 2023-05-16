//
//  KnownSource.swift
//  AltStore
//
//  Created by Riley Testut on 5/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

struct KnownSource: Decodable
{
    var identifier: String
    var sourceURL: URL?
    var bundleIDs: [String]?
}

private extension KnownSource
{
    var dictionaryRepresentation: [String: Any] {
        let dictionary: [String: Any?] = [
            KnownSource.CodingKeys.identifier.stringValue: identifier,
            KnownSource.CodingKeys.sourceURL.stringValue: self.sourceURL?.absoluteString,
            KnownSource.CodingKeys.bundleIDs.stringValue: self.bundleIDs
        ]
        
        return dictionary.compactMapValues { $0 }
    }
    
    init?(dictionary: [String: Any])
    {
        guard let identifier = dictionary[CodingKeys.identifier.stringValue] as? String else { return nil }
        self.identifier = identifier
        
        if let sourceURLString = dictionary[CodingKeys.sourceURL.stringValue] as? String
        {
            self.sourceURL = URL(string: sourceURLString)
        }
        
        let bundleIDs = dictionary[CodingKeys.bundleIDs.stringValue] as? [String]
        self.bundleIDs = bundleIDs
    }
}

extension UserDefaults
{
    // Cache trusted sources just in case we need to check whether source is trusted or not.
    @nonobjc var trustedSources: [KnownSource]? {
        get {
            guard let sources = _trustedSources?.compactMap({ KnownSource(dictionary: $0) }) else { return nil }
            return sources
        }
        set {
            _trustedSources = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    @NSManaged @objc(trustedSources) private var _trustedSources: [[String: Any]]?
    
    @nonobjc var blockedSources: [KnownSource]? {
        get {
            guard let sources = _blockedSources?.compactMap({ KnownSource(dictionary: $0) }) else { return nil }
            return sources
        }
        set {
            _blockedSources = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    @NSManaged @objc(blockedSources) private var _blockedSources: [[String: Any]]?
}
