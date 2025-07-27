//
//  FetchSourceOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore
import Roxas

@objc(FetchSourceOperation)
class FetchSourceOperation: ResultOperation<Source>, @unchecked Sendable
{
    let sourceURL: URL
    let managedObjectContext: NSManagedObjectContext
    
    // Non-nil when updating an existing source.
    @Managed
    private var source: Source?
    
    private let session: URLSession
    private weak var dataTask: URLSessionDataTask?
    
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter
    }()
    
    // New source
    convenience init(sourceURL: URL, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.init(sourceURL: sourceURL, source: nil, managedObjectContext: managedObjectContext)
    }
    
    // Existing source
    convenience init(source: Source, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.init(sourceURL: source.sourceURL, source: source, managedObjectContext: managedObjectContext)
    }
    
    private init(sourceURL: URL, source: Source?, managedObjectContext: NSManagedObjectContext)
    {
        self.sourceURL = sourceURL
        self.managedObjectContext = managedObjectContext
        self.source = source
        
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        self.session = URLSession(configuration: configuration)
    }
    
    override func cancel() 
    {
        super.cancel()
        
        self.dataTask?.cancel()
    }
    
    override func main()
    {
        super.main()
        
        if let source = self.source
        {
            // Check if source is blocked before fetching it.
            
            do
            {
                try self.managedObjectContext.performAndWait {
                    // Source must be from self.managedObjectContext
                    let source = self.managedObjectContext.object(with: source.objectID) as! Source
                    try self.verifySourceNotBlocked(source, response: nil)
                }
            }
            catch
            {
                self.managedObjectContext.perform {
                    self.finish(.failure(error))
                }
                
                return
            }
        }
        
        let dataTask = self.session.dataTask(with: self.sourceURL) { (data, response, error) in
            
            let childContext = DatabaseManager.shared.persistentContainer.newBackgroundContext(withParent: self.managedObjectContext)
            childContext.mergePolicy = NSOverwriteMergePolicy
            childContext.perform {
                do
                {
                    let (data, response) = try Result((data, response), error).get()
                    
                    let decoder = AltStoreCore.JSONDecoder()
                    decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
                        let container = try decoder.singleValueContainer()
                        let text = try container.decode(String.self)
                        
                        // Full ISO8601 Format.
                        self.dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
                        if let date = self.dateFormatter.date(from: text)
                        {
                            return date
                        }
                        
                        // Just date portion of ISO8601.
                        self.dateFormatter.formatOptions = [.withFullDate]
                        if let date = self.dateFormatter.date(from: text)
                        {
                            return date
                        }
                        
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date is in invalid format.")
                    })
                    
                    decoder.managedObjectContext = childContext
                    decoder.sourceURL = self.sourceURL
                    
                    if #available(iOS 15, *)
                    {
                        decoder.allowsJSON5 = true
                    }
                    
                    let source: Source
                    
                    do
                    {
                        source = try decoder.decode(Source.self, from: data)
                    }
                    catch let error as DecodingError
                    {
                        let nsError = error as NSError
                        guard var codingPath = nsError.userInfo[ALTNSCodingPathKey] as? [CodingKey] else { throw error }
                        
                        if case .keyNotFound(let key, _) = error
                        {
                            // Add missing key to error for better debugging.
                            codingPath.append(key)
                        }
                        
                        let rawComponents = codingPath.map { $0.intValue?.description ?? $0.stringValue }
                        let pathDescription = rawComponents.joined(separator: " > ")
                        
                        var userInfo = nsError.userInfo
                        
                        if let debugDescription = nsError.localizedDebugDescription
                        {
                            let detailedDescription = debugDescription + "\n\n" + pathDescription
                            userInfo[NSDebugDescriptionErrorKey] = detailedDescription
                        }
                        else
                        {
                            userInfo[NSDebugDescriptionErrorKey] = pathDescription
                        }
                        
                        throw NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfo)
                    }
                    
                    let identifier = source.identifier
                    
                    if identifier == Source.altStoreIdentifier, let skipPatreonDownloads = source.userInfo?[.skipPatreonDownloads]
                    {
                        UserDefaults.shared.skipPatreonDownloads = (skipPatreonDownloads == "true")
                    }
                    
                    try self.verify(source, response: response)
                    try self.verifyPledges(for: source, in: childContext)
                    
                    try childContext.save()
                    
                    self.managedObjectContext.perform {
                        if let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), identifier), in: self.managedObjectContext)
                        {
                            self.finish(.success(source))
                        }
                        else
                        {
                            self.finish(.failure(OperationError.noSources))
                        }
                    }
                }
                catch
                {
                    self.managedObjectContext.perform {
                        self.finish(.failure(error))
                    }
                }
            }
        }
        
        self.progress.addChild(dataTask.progress, withPendingUnitCount: 1)
        
        dataTask.resume()
        
        self.dataTask = dataTask
    }
}

private extension FetchSourceOperation
{
    func verify(_ source: Source, response: URLResponse) throws
    {
        try self.verifySourceNotBlocked(source, response: response)
        
        var bundleIDs = Set<String>()
        for app in source.apps
        {
            guard !bundleIDs.contains(app.bundleIdentifier) else { throw SourceError.duplicateBundleID(app.bundleIdentifier, source: source) }
            bundleIDs.insert(app.bundleIdentifier)

            var versions = Set<String>()
            for version in app.versions
            {
                guard !versions.contains(version.versionID) else { throw SourceError.duplicateVersion(version.localizedVersion, for: app, source: source) }
                versions.insert(version.versionID)
            }
            
            for permission in app.permissions where permission.type == .privacy
            {
                // Privacy permissions MUST have a usage description.
                guard permission.usageDescription != nil else { throw SourceError.missingPermissionUsageDescription(for: permission.permission, app: app, source: source) }
            }
            
            for screenshot in app.screenshots(for: .ipad)
            {
                // All iPad screenshots MUST have an explicit size.
                guard screenshot.size != nil else { throw SourceError.missingScreenshotSize(for: screenshot, source: source) }
            }
            
            #if MARKETPLACE
            guard app.marketplaceID != nil else { throw SourceError.marketplaceRequired(source: source) }
            #else
            guard app.marketplaceID == nil else { throw SourceError.marketplaceNotSupported(source: source) }
            #endif
        }
        
        if let previousSourceID = self.$source.identifier
        {
            guard source.identifier == previousSourceID else { throw SourceError.changedID(source.identifier, previousID: previousSourceID, source: source) }
        }
    }
    
    func verifyPledges(for source: Source, in context: NSManagedObjectContext) throws
    {
        guard let patreonURL = source.patreonURL, let patreonAccount = DatabaseManager.shared.patreonAccount(in: context) else { return }
        
        let normalizedPatreonURL = try patreonURL.normalized()
        
        guard let pledge = patreonAccount.pledges.first(where: { pledge in
            do
            {
                let normalizedCampaignURL = try pledge.campaignURL.normalized()
                return normalizedCampaignURL == normalizedPatreonURL
            }
            catch
            {
                Logger.main.error("Failed to normalize Patreon URL \(pledge.campaignURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
                return false
            }
        }) else { return }
        
        // User is pledged to this source's Patreon, so check which apps they're pledged to.
        
        // We only assign `isPledged = true` because false is already the default,
        // and only one check needs to be true for isPledged to be true.
        
        if normalizedPatreonURL == "patreon.com/rileyshane", let promoExpiration = Keychain.shared.palPromoExpiration, Date.now < promoExpiration
        {
            // User has promotional access to our betas, so treat all beta apps as if we've already pledged.
            
            for app in source.apps where app.isPledgeRequired
            {
                app.isPledged = true
            }
            
            return
        }
        
        for app in source.apps where app.isPledgeRequired
        {
            if let requiredAppPledge = app.pledgeAmount
            {
                if pledge.amount >= requiredAppPledge
                {
                    app.isPledged = true
                    continue
                }
            }
            
            if let tierIDs = app._tierIDs
            {
                let tier = pledge.tiers.first { tierIDs.contains($0.identifier) }
                if tier != nil
                {
                    app.isPledged = true
                    continue
                }
            }
                                
            if let rewardID = app._rewardID
            {
                let reward = pledge.rewards.first { $0.identifier == rewardID }
                if reward != nil
                {
                    app.isPledged = true
                    continue
                }
            }
        }
    }
    
    func verifySourceNotBlocked(_ source: Source, response: URLResponse?) throws
    {
        guard let blockedSources = UserDefaults.shared.blockedSources else { return }
        
        for blockedSource in blockedSources
        {
            guard
                source.identifier != blockedSource.identifier,
                source.sourceURL.absoluteString.lowercased() != blockedSource.sourceURL?.absoluteString.lowercased()
            else { throw SourceError.blocked(source, bundleIDs: blockedSource.bundleIDs, existingSource: self.source) }
            
            if let responseURL = response?.url
            {
                // responseURL may differ from source.sourceURL (e.g. due to redirects), so double-check it's also not blocked.
                guard responseURL.absoluteString.lowercased() != blockedSource.sourceURL?.absoluteString.lowercased() else {
                    throw SourceError.blocked(source, bundleIDs: blockedSource.bundleIDs, existingSource: self.source)
                }
            }
        }
    }
}
