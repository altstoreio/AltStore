//
//  Managed.swift
//  AltStore
//
//  Created by Riley Testut on 10/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@propertyWrapper @dynamicMemberLookup
public struct Managed<ManagedObject>
{
    public var wrappedValue: ManagedObject {
        didSet {
            self.managedObjectContext = self.managedObject?.managedObjectContext
        }
    }
    
    public var projectedValue: Managed<ManagedObject> {
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
public extension Managed
{
    // Non-throwing
    func perform<T>(_ closure: @escaping (ManagedObject) -> T) -> T
    {
        let result: T
        
        if let context = self.managedObjectContext
        {
            result = context.performAndWait {
                closure(self.wrappedValue)
            }
        }
        else
        {
            result = closure(self.wrappedValue)
        }
        
        return result
    }
    
    // Throwing
    func perform<T>(_ closure: @escaping (ManagedObject) throws -> T) throws -> T
    {
        let result: T
        
        if let context = self.managedObjectContext
        {
            result = try context.performAndWait {
                try closure(self.wrappedValue)
            }
        }
        else
        {
            result = try closure(self.wrappedValue)
        }
        
        return result
    }
}

/// @dynamicMemberLookup
public extension Managed
{
    // Non-optional values
    subscript<T>(dynamicMember keyPath: KeyPath<ManagedObject, T>) -> T
    {
        let result = self.perform { $0[keyPath: keyPath] }
        return result
    }
    
    // Optional wrapped value
    subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T? where ManagedObject == Optional<Wrapped>
    {
        guard let wrappedValue else { return nil }
        
        let result = self.perform { _ in wrappedValue[keyPath: keyPath] }
        return result
    }
    
    // Optional wrapped value + optional property (flattened)
    subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T where ManagedObject == Optional<Wrapped>, T: OptionalProtocol
    {
        guard let wrappedValue else { return T.none }
        
        let result = self.perform { _ in wrappedValue[keyPath: keyPath] }
        return result
    }
}
