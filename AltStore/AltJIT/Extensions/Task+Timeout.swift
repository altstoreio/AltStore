//
//  Task+Timeout.swift
//  AltPackage
//
//  Created by Riley Testut on 8/31/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
//  Based heavily on https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/13
//

import Foundation

struct TimedOutError: LocalizedError
{
    var duration: TimeInterval
    
    public var errorDescription: String? {
        //TODO: Change pluralization for 1 second.
        let errorDescription = String(format: NSLocalizedString("The task timed out after %@ seconds.", comment: ""), self.duration.formatted())
        return errorDescription
    }
}

///
/// Execute an operation in the current task subject to a timeout.
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
func withTimeout<R>(seconds: TimeInterval, file: StaticString = #file, line: Int = #line, operation: @escaping @Sendable () async throws -> R) async throws -> R
{
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            return try await operation()
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(for: .seconds(interval))
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw TimedOutError(duration: seconds)
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
