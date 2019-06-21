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
    
    var server: Server?
    var signer: ALTSigner?
    
    var error: Error?
    
    var results = [String: Result<InstalledApp, Error>]()
    
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
}
