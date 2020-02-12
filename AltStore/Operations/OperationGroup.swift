//
//  OperationGroup.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

class OperationGroup
{
    let progress = Progress.discreteProgress(totalUnitCount: 0)
    
    var completionHandler: ((Result<[String: Result<InstalledApp, Error>], Error>) -> Void)?
    var beginInstallationHandler: ((InstalledApp) -> Void)?
    
    var session: ALTAppleAPISession?
    
    var server: Server?
    var signer: ALTSigner?
    
    var error: Error?
    
    var results = [String: Result<InstalledApp, Error>]()
    
    private var progressByBundleIdentifier = [String: Progress]()
    
    private let operationQueue = OperationQueue()
    private let installOperationQueue = OperationQueue()
    
    init()
    {
        // Enforce only one installation at a time.
        self.installOperationQueue.maxConcurrentOperationCount = 1
    }
    
    func cancel()
    {
        self.operationQueue.cancelAllOperations()
        self.installOperationQueue.cancelAllOperations()
    }
    
    func addOperations(_ operations: [Operation])
    {
        for operation in operations
        {
            if let installOperation = operation as? InstallAppOperation
            {
                if let previousOperation = self.installOperationQueue.operations.last
                {
                    // Ensures they execute in the order they're added, since isReady is still false at this point.
                    installOperation.addDependency(previousOperation)
                }
                
                self.installOperationQueue.addOperation(installOperation)
            }
            else
            {
                self.operationQueue.addOperation(operation)
            }
        }
    }
    
    func set(_ progress: Progress, for app: AppProtocol)
    {
        self.progressByBundleIdentifier[app.bundleIdentifier] = progress
        
        self.progress.totalUnitCount += 1
        self.progress.addChild(progress, withPendingUnitCount: 1)
    }
    
    func progress(for app: AppProtocol) -> Progress?
    {
        return self.progress(forAppWithBundleIdentifier: app.bundleIdentifier)
    }
    
    func progress(forAppWithBundleIdentifier bundleIdentifier: String) -> Progress?
    {
        let progress = self.progressByBundleIdentifier[bundleIdentifier]
        return progress
    }
}
