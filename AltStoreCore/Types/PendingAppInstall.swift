//
//  PendingAppInstall.swift
//  AltStoreCore
//
//  Created by Riley Testut on 2/23/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import Foundation

import MarketplaceKit

public struct PendingAppInstall: Codable
{
    public var appleItemID: AppleItemID
    public var adpURL: URL
    public var version: String
    public var buildVersion: String
    public var installVerificationToken: String
}
