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
struct Managed<ManagedObject>
{
    var wrappedValue: ManagedObject {
        didSet {
            self.managedObjectContext = self.managedObject?.managedObjectContext
        }
    }
    
    var projectedValue: Managed<ManagedObject> {
        return self
    }
    
    private var managedObjectContext: NSManagedObjectContext?
    private var managedObject: NSManagedObject? {
        return self.wrappedValue as? NSManagedObject
    }
    
    init(wrappedValue: ManagedObject)
    {
        self.wrappedValue = wrappedValue
        self.managedObjectContext = self.managedObject?.managedObjectContext
    }
    
    subscript<T>(dynamicMember keyPath: KeyPath<ManagedObject, T>) -> T
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
    subscript<Wrapped, T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T? where ManagedObject == Optional<Wrapped>
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
}
