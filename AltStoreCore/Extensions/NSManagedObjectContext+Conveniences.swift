//
//  NSManagedObjectContext+Conveniences.swift
//  AltStore
//
//  Created by Riley Testut on 5/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import CoreData

public extension NSManagedObjectContext
{
    // Non-throwing
    func performAndWait<T>(_ closure: @escaping () -> T) -> T
    {
        var result: T!
        
        self.performAndWait {
            result = closure()
        }
        
        return result
    }
    
    // Throwing
    func performAndWait<T>(_ closure: @escaping () throws -> T) throws -> T
    {
        var result: Result<T, Error>!
        
        self.performAndWait {
            result = Result { try closure() }
        }
        
        let value = try result.get()
        return value
    }
}
