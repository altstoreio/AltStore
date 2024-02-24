//
//  InstallAppRequest.swift
//  AltMarketplace
//
//  Created by Riley Testut on 2/23/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import Foundation
import MarketplaceKit

public struct InstallAppRequest: Decodable
{
    public struct App: Codable
    {
        public var appleItemId: String
        public var appleVersionId: String
    }
    
    public var apps: [App]
    
    public var platform: String // "ios"
    public var osVersion: String
}
