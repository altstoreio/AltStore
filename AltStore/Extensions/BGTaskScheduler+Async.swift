//
//  BGTaskScheduler+Async.swift
//  AltStore
//
//  Created by Riley Testut on 8/19/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import BackgroundTasks

@available(iOS 26, *)
extension BGTaskScheduler
{
    func startBackgroundTask<T>(
        identifier taskID: String,
        title: String,
        subtitle: String,
        task handler: @escaping (BGContinuedProcessingTask) async throws -> T,
        expiration expirationHandler: @escaping () -> Void = {}) async throws -> T
    {
        let request = BGContinuedProcessingTaskRequest(identifier: taskID, title: title, subtitle: subtitle)
        request.strategy = .fail // Throw error when submitting request below if we can't start task instead of queueing for later.
        
        return try await withCheckedThrowingContinuation { continuation in
            self.register(forTaskWithIdentifier: taskID, using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                task.expirationHandler = expirationHandler
                
                Task<Void, Never> {
                    do
                    {
                        let result = try await handler(task)
                        
                        task.setTaskCompleted(success: true)
                        continuation.resume(returning: result)
                    }
                    catch
                    {
                        task.setTaskCompleted(success: false)
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            do
            {
                try self.submit(request)
            }
            catch
            {
                continuation.resume(throwing: error)
            }
        }
    }
}
