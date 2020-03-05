//
//  RefreshGroup.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign

class RefreshGroup: NSObject
{
    let context: AuthenticatedOperationContext
    let progress = Progress.discreteProgress(totalUnitCount: 0)
    
    var completionHandler: ((Result<[String: Result<InstalledApp, Error>], Error>) -> Void)?
    
    private var isFinished = false
        
    private var progressByBundleID = [String: Progress]()
    private var resultsByBundleID = [String: Result<InstalledApp, Error>]()
    
    private let operationQueue = OperationQueue()
    private let finishOperation = BlockOperation()
    
    init(context: AuthenticatedOperationContext = AuthenticatedOperationContext())
    {
        self.context = context
        
        super.init()
        
        self.finishOperation.addExecutionBlock { [weak self] in
            self?.finish()
        }
        
        self.operationQueue.isSuspended = true
        self.operationQueue.addOperation(self.finishOperation)
    }
    
    func finish()
    {
        guard !self.isFinished else { return }
        self.isFinished = true
        
        if let error = self.context.error
        {
            self.completionHandler?(.failure(error))
        }
        else
        {
            self.completionHandler?(.success(self.resultsByBundleID))
        }
    }
    
    func cancel()
    {
        self.operationQueue.cancelAllOperations()
    }
    
    func add(_ operations: [Foundation.Operation])
    {
        operations.forEach { self.finishOperation.addDependency($0) }
        self.operationQueue.isSuspended = false
    }
//
//    func progress(forAppWithBundleIdentifier bundleIdentifier: String) -> Progress?
//    {
//        let progress = self.progressByBundleID[bundleIdentifier]
//        return progress
//    }
//
    func set(_ result: Result<InstalledApp, Error>, forAppWithBundleIdentifier bundleIdentifier: String)
    {
        self.resultsByBundleID[bundleIdentifier] = result
    }
}
