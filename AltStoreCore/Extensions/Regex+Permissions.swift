//
//  Regex+Permissions.swift
//  AltStore
//
//  Created by Riley Testut on 10/10/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import RegexBuilder

@available(iOS 16, *)
public extension Regex where Output == (Substring, Substring)
{
    static var privacyPermission: some RegexComponent<(Substring, Substring)> {
        Regex {
            Optionally {
                "NS"
            }
            
            // Capture permission "name"
            Capture {
                OneOrMore(.anyGraphemeCluster)
            }
            
            "UsageDescription"
            
            // Optional suffix
            Optionally(OneOrMore(.anyGraphemeCluster))
        }
    }
}
