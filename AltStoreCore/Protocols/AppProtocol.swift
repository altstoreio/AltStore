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
    var url: URL? { get }
    
    var storeApp: StoreApp? { get }
}

public struct AnyApp: AppProtocol
{
    public var name: String
    public var bundleIdentifier: String
    public var url: URL?
    public var storeApp: StoreApp?
    
    public init(name: String, bundleIdentifier: String, url: URL?, storeApp: StoreApp?)
    {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.storeApp = storeApp
    }
}

extension ALTApplication: AppProtocol
{
    public var url: URL? {
        return self.fileURL
    }
    
    public var storeApp: StoreApp? {
        return nil
    }
}

extension StoreApp: AppProtocol
{
    public var url: URL? {
        return self.latestAvailableVersion?.downloadURL
    }
    
    public var storeApp: StoreApp? {
        return self
    }
}

extension InstalledApp: AppProtocol
{
    public var url: URL? {
        return self.fileURL
    }
}

extension AppVersion: AppProtocol
{
    public var name: String {
        return self.app?.name ?? self.bundleIdentifier
    }
    
    public var bundleIdentifier: String {
        return self.appBundleID
    }
    
    public var url: URL? {
        return self.downloadURL
    }
    
    public var storeApp: StoreApp? {
        return self.app
    }
}
