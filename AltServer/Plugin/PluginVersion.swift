//
//  PluginVersion.swift
//  AltServer
//
//  Created by Riley Testut and Weedles on 2/15/22 <3
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

struct PluginVersion: Decodable
{
    var url: URL
    var sha256Hash: String
    var version: String
    
    static let v1_0 = PluginVersion(url: URL(string: "https://f000.backblazeb2.com/file/altstore/altserver/altplugin/1_0.zip")!,
                                      sha256Hash: "070e9b7e1f74e7a6474d36253ab5a3623ff93892acc9e1043c3581f2ded12200",
                                      version: "1.0")
    
    static let v1_9 = PluginVersion(url: Bundle.main.url(forResource: "AltPlugin", withExtension: "zip")!,
                                       sha256Hash: "83ead26d8776ef6850e06fe3d1c5c5559aca284718b1cf3cc49785ba6b1e2849",
                                       version: "1.9")
    
    private enum CodingKeys: String, CodingKey
    {
        case url
        case sha256Hash = "sha256"
        case version
    }
}

struct PluginVersionResponse: Decodable
{
    var version: Int
    var pluginVersion: PluginVersion
}
