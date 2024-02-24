//
//  AltMarketplace.swift
//  AltMarketplace
//
//  Created by Riley Testut on 1/26/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import Foundation
import ExtensionFoundation
import MarketplaceKit

import AltStoreCore

@main
final class AltMarketplace: MarketplaceExtension
{
    required init()
    {
        // Initialize your extension here.
    }
    
    func additionalHeaders(for request: URLRequest, account: String) -> [String : String]?
    {
        //TODO: Does iOS automatically provide the OAuth Bearer token? Or do we need to provide it ourselves?
        
        guard let requestURL = request.url, requestURL.path().contains("restore") || requestURL.path().contains("update") else { return nil }
        
        var additionalHeaders = [String: String]()
        
        do
        {
            guard let data = request.httpBody else { throw URLError(URLError.Code.unsupportedURL) }
            
            switch requestURL.path()
            {
            case let path where path.lowercased().contains("restore"):
                // Installing app
                
                let payload = try Foundation.JSONDecoder().decode(InstallAppRequest.self, from: data)
                
                for app in payload.apps
                {
                    // Provide download URL + install in headers.
                    guard let marketplaceID = AppleItemID(app.appleItemId), let pendingInstall = try Keychain.shared.pendingInstall(for: marketplaceID) else { continue }
                    
                    let adpHeader = HTTPHeader.adpURL(for: marketplaceID)
                    let installTokenHeader = HTTPHeader.installVerificationToken(for: marketplaceID) //TODO: Do we need to provide install token? Or does server re-generate it?
                    
                    additionalHeaders[adpHeader.rawValue] = pendingInstall.adpURL.absoluteString
                    additionalHeaders[installTokenHeader.rawValue] = pendingInstall.installVerificationToken
                }
                
                break
                
            case let path where path.lowercased().contains("update"):
                // Updating app
                
                let payload = try Foundation.JSONDecoder().decode(InstallAppRequest.self, from: data)
                
                for app in payload.apps
                {
                    // Provide app info in headers.
                    guard let marketplaceID = AppleItemID(app.appleItemId), let pendingInstall = try Keychain.shared.pendingInstall(for: marketplaceID) else { continue }
                    
                    let adpHeader = HTTPHeader.adpURL(for: marketplaceID)
                    let versionHeader = HTTPHeader.version(for: marketplaceID)
                    let buildVersionHeader = HTTPHeader.buildVersion(for: marketplaceID)
                    let installTokenHeader = HTTPHeader.installVerificationToken(for: marketplaceID) //TODO: Do we need to provide install token? Or does server re-generate it?
                    
                    additionalHeaders[adpHeader.rawValue] = pendingInstall.adpURL.absoluteString
                    additionalHeaders[versionHeader.rawValue] = pendingInstall.version
                    additionalHeaders[buildVersionHeader.rawValue] = pendingInstall.buildVersion
                    additionalHeaders[installTokenHeader.rawValue] = pendingInstall.installVerificationToken
                }
                
                break
                
            default: break
            }
        }
        catch
        {
            Logger.main.error("Failed to provide additional headers for request \(request, privacy: .public). \(error.localizedDescription, privacy: .public)")
        }
        
        return additionalHeaders
    }
    
    func availableAppVersions(forAppleItemIDs ids: [AppleItemID]) -> [MarketplaceKit.AppVersion]?
    {
        return []
    }
    
    func requestFailed(with response: HTTPURLResponse) -> Bool
    {
        return false
    }
    
    func automaticUpdates(for installedAppVersions: [MarketplaceKit.AppVersion]) async throws -> [AutomaticUpdate]
    {
        return []
    }
}
