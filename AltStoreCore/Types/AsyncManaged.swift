//
//  AsyncManaged.swift
//  AltStore
//
//  Created by Riley Testut on 3/30/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@propertyWrapper @dynamicMemberLookup
public struct AsyncManaged<ManagedObject>
{
    public var wrappedValue: ManagedObject {
        didSet {
            self.managedObjectContext = self.managedObject?.managedObjectContext
        }
    }
    
    public var projectedValue: AsyncManaged<ManagedObject> {
        return self
    }
    
    private var managedObjectContext: NSManagedObjectContext?
    private var managedObject: NSManagedObject? {
        return self.wrappedValue as? NSManagedObject
    }
    
    public init(wrappedValue: ManagedObject)
    {
        self.wrappedValue = wrappedValue
        self.managedObjectContext = self.managedObject?.managedObjectContext
    }
}

/// Run on managedObjectContext's queue.
public extension AsyncManaged
{
    // Non-throwing
    func perform<T>(_ closure: @escaping (ManagedObject) -> T) async -> T
    {
        if let context = self.managedObjectContext
        {
            return await context.performAsync {
                closure(self.wrappedValue)
            }
        }
        else
        {
            return closure(self.wrappedValue)
        }
    }
    
    // Throwing
    func perform<T>(_ closure: @escaping (ManagedObject) throws -> T) async throws -> T
    {
        if let context = self.managedObjectContext
        {
            return try await context.performAsync {
                try closure(self.wrappedValue)
            }
        }
        else
        {
            return try closure(self.wrappedValue)
        }
    }
}

/// @dynamicMemberLookup
public extension AsyncManaged
{
    // Non-optional values
    subscript<T>(dynamicMember keyPath: KeyPath<ManagedObject, T>) -> T {
        get async {
            let result = await self.perform { $0[keyPath: keyPath] }
            return result
        }
    }

    // Optional wrapped value
    subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T? where ManagedObject == Optional<Wrapped> {
        get async {
            guard let wrappedValue else { return nil }
            
            let result = await self.perform { _ in wrappedValue[keyPath: keyPath] }
            return result
        }
    }
    
    // Optional wrapped value + optional property (flattened)
    subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T where ManagedObject == Optional<Wrapped>, T: OptionalProtocol {
        get async {
            guard let wrappedValue else { return T.none }
            
            let result = await self.perform { _ in wrappedValue[keyPath: keyPath] }
            return result
        }
    }
}
