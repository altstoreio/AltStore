//
//  AppProtocol.swift
//  AltStore
//
//  Created by Riley Testut on 7/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

public protocol AppProtocol
{
    var name: String { get }
    var bundleIdentifier: String { get }
    var url: URL { get }
}

extension ALTApplication: AppProtocol
{
    public var url: URL {
        return self.fileURL
    }
}

extension StoreApp: AppProtocol
{
    public var url: URL {
        return self.downloadURL
    }
}

extension InstalledApp: AppProtocol
{
    public var url: URL {
        return self.fileURL
    }
}
