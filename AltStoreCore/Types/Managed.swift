//
//  Managed.swift
//  AltStore
//
//  Created by Riley Testut on 10/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

// Public so we can use as generic constraint.
public protocol OptionalProtocol
{
    associatedtype Wrapped
    
    static var none: Self { get }
    
    static var wrappedType: Wrapped.Type { get }
}

extension Optional: OptionalProtocol
{
    public static var wrappedType: Wrapped.Type { return Wrapped.self }
}


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
    
    public subscript<T>(dynamicMember keyPath: KeyPath<ManagedObject, T>) -> T
    {
        var result: T!
        
        if let context = self.managedObjectContext
        {
            context.performAndWait {
                result = self.wrappedValue[keyPath: keyPath]
            }
        }
        else
        {
            result = self.wrappedValue[keyPath: keyPath]
        }
        
        return result
    }
    
    // Optionals
    public subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T? where ManagedObject == Optional<Wrapped>
    {
        var result: T?
        
        if let context = self.managedObjectContext
        {
            context.performAndWait {
                result = self.wrappedValue?[keyPath: keyPath] as? T
            }
        }
        else
        {
            result = self.wrappedValue?[keyPath: keyPath] as? T
        }
        
        return result
    }
    
    public subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T where ManagedObject == Optional<Wrapped>, T: OptionalProtocol
    {
        var result: T!
        
        if let context = self.managedObjectContext
        {
            context.performAndWait {
                result = self.wrappedValue?[keyPath: keyPath]
            }
        }
        else
        {
            result = self.wrappedValue?[keyPath: keyPath]
        }
        
        return result
    }
}

public extension Managed
{
    // Fetch multiple values.
    func get<T>(_ closure: @escaping (ManagedObject) -> T) -> T
    {
        var result: T!
        
        if let context = self.managedObjectContext
        {
            context.performAndWait {
                result = closure(self.wrappedValue)
            }
        }
        else
        {
            result = closure(self.wrappedValue)
        }
        
        return result
    }
}
