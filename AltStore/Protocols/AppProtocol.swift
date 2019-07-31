//
//  AppProtocol.swift
//  AltStore
//
//  Created by Riley Testut on 7/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

protocol AppProtocol
{
    var name: String { get }
    var bundleIdentifier: String { get }
    var url: URL { get }
}

extension ALTApplication: AppProtocol
{
    var url: URL {
        return self.fileURL
    }
}

extension StoreApp: AppProtocol
{
    var url: URL {
        return self.downloadURL
    }
}

extension InstalledApp: AppProtocol
{
    var url: URL {
        return self.fileURL
    }
}
