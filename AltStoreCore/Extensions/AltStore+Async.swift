//
//  AltStore+Async.swift
//  AltStoreCore
//
//  Created by Riley Testut on 3/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import CoreData

public extension NSManagedObjectContext
{
    func performAsync<T>(_ closure: @escaping () throws -> T) async throws -> T
    {
        let result: T
        
        if #available(iOS 15, *)
        {
            result = try await self.perform(schedule: .immediate) {
                try closure()
            }
        }
        else
        {
            result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                self.perform {
                    let result = Result { try closure() }
                    continuation.resume(with: result)
                }
            }
        }
        
        return result
    }
}
