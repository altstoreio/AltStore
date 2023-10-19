//
//  DatabaseManager+Async.swift
//  AltStoreCore
//
//  Created by Riley Testut on 8/22/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

public extension DatabaseManager
{
    func start() async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.start { error in
                if let error
                {
                    continuation.resume(throwing: error)
                }
                else
                {
                    continuation.resume()
                }
            }
        }
    }
}
