//
//  NSManagedObject+Conveniences.swift
//  AltStore
//
//  Created by Riley Testut on 6/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

public typealias FetchRequest = NSFetchRequest<NSFetchRequestResult>

public protocol Fetchable: NSManagedObject
{
}

public extension Fetchable
{
    static func first(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext,
                      requestProperties: [PartialKeyPath<FetchRequest>: Any?] = [:]) -> Self?
    {
        let managedObjects = Self.all(satisfying: predicate, sortedBy: sortDescriptors, in: context, requestProperties: requestProperties, returnFirstResult: true)
        return managedObjects.first
    }
    
    static func all(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext,
                    requestProperties: [PartialKeyPath<FetchRequest>: Any?] = [:]) -> [Self]
    {
        let managedObjects = Self.all(satisfying: predicate, sortedBy: sortDescriptors, in: context, requestProperties: requestProperties, returnFirstResult: false)
        return managedObjects
    }
    
    static func fetch(_ fetchRequest: NSFetchRequest<Self>, in context: NSManagedObjectContext) -> [Self]
    {
        do
        {
            let managedObjects = try context.fetch(fetchRequest)
            return managedObjects
        }
        catch
        {
            print("Failed to fetch managed objects. Fetch Request: \(fetchRequest). Error: \(error).")
            return []
        }
    }
    
    private static func all(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext, requestProperties: [PartialKeyPath<FetchRequest>: Any?], returnFirstResult: Bool) -> [Self]
    {
        let registeredObjects = context.registeredObjects.lazy.compactMap({ $0 as? Self }).filter({ predicate?.evaluate(with: $0) != false })
        
        if let managedObject = registeredObjects.first, returnFirstResult
        {
            return [managedObject]
        }
        
        let fetchRequest = self.fetchRequest() as! NSFetchRequest<Self>
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        for (keyPath, value) in requestProperties
        {
            // Still no easy way to cast PartialKeyPath back to usable WritableKeyPath :(
            guard let objcKeyString = keyPath._kvcKeyPathString else { continue }
            fetchRequest.setValue(value, forKey: objcKeyString)
        }
        
        let fetchedObjects = self.fetch(fetchRequest, in: context)
        
        if let fetchedObject = fetchedObjects.first, returnFirstResult
        {
            return [fetchedObject]
        }
        else
        {
            return fetchedObjects
        }
    }
}
