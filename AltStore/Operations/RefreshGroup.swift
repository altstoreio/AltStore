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
    
    var completionHandler: (([String: Result<InstalledApp, Error>]) -> Void)?
    var beginInstallationHandler: ((InstalledApp) -> Void)?
        
    private(set) var results = [String: Result<InstalledApp, Error>]()
    
    private var isFinished = false
    
    private let dispatchGroup = DispatchGroup()
    private var operations: [Foundation.Operation] = []
    
    init(context: AuthenticatedOperationContext = AuthenticatedOperationContext())
    {
        self.context = context
        
        super.init()
    }
    
    func add(_ operations: [Foundation.Operation])
    {
        for operation in operations
        {
            self.dispatchGroup.enter()
            
            operation.completionBlock = { [weak self] in
                self?.dispatchGroup.leave()
            }
        }
        
        if self.operations.isEmpty && !operations.isEmpty
        {
            self.dispatchGroup.notify(queue: .global()) { [weak self] in
                self?.finish()
            }
        }
        
        self.operations.append(contentsOf: operations)
    }
    
    func set(_ result: Result<InstalledApp, Error>, forAppWithBundleIdentifier bundleIdentifier: String)
    {
        self.results[bundleIdentifier] = result
    }
    
    func cancel()
    {
        self.operations.forEach { $0.cancel() }
    }
}

private extension RefreshGroup
{
    func finish()
    {
        guard !self.isFinished else { return }
        self.isFinished = true
        
        self.completionHandler?(self.results)
    }
}
