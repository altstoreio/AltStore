//
//  Operation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Roxas

class ResultOperation<ResultType>: Operation, @unchecked Sendable
{
    var resultHandler: ((Result<ResultType, Error>) -> Void)?
    
    // Should only be set by subclasses.
    var localizedFailure: String?
    
    @available(*, unavailable)
    override func finish()
    {
        super.finish()
    }

    func finish(_ result: Result<ResultType, Error>)
    {
        guard !self.isFinished else { return }
        
        var result = result
        
        if self.isCancelled
        {
            result = .failure(OperationError.cancelled)
        }
        else if case .failure(let nsError as NSError) = result, let localizedFailure, nsError.localizedFailure == nil
        {
            // Error does not have localizedFailure, so give it the Operation's failure (if one exists).
            let error = nsError.withLocalizedFailure(localizedFailure)
            result = .failure(error)
        }
        
        self.resultHandler?(result)
        
        super.finish()
    }
}

class Operation: RSTOperation, ProgressReporting, @unchecked Sendable
{
    let progress = Progress.discreteProgress(totalUnitCount: 1)
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier?
    
    override var isAsynchronous: Bool {
        return true
    }
    
    override init()
    {
        super.init()
        
        self.progress.cancellationHandler = { [weak self] in self?.cancel() }
    }
    
    override func cancel()
    {
        super.cancel()
        
        if !self.progress.isCancelled
        {
            self.progress.cancel()
        }
    }
    
    override func main()
    {
        super.main()
        
        let name = "com.altstore." + NSStringFromClass(type(of: self))
        self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let backgroundTask = self?.backgroundTaskID else { return }
            
            self?.cancel()
            
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self?.backgroundTaskID = .invalid
        }        
    }
    
    override func finish()
    {
        guard !self.isFinished else { return }
        
        super.finish()
        
        if let backgroundTaskID = self.backgroundTaskID
        {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
    }
}
