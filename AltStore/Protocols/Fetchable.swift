//
//  NSManagedObject+Conveniences.swift
//  AltStore
//
//  Created by Riley Testut on 6/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

protocol Fetchable: NSManagedObject
{
}

extension Fetchable
{
    static func first(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext) -> Self?
    {
        let managedObjects = Self.all(satisfying: predicate, sortedBy: sortDescriptors, in: context, returnFirstResult: true)
        return managedObjects.first
    }
    
    static func all(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext) -> [Self]
    {
        let managedObjects = Self.all(satisfying: predicate, sortedBy: sortDescriptors, in: context, returnFirstResult: false)
        return managedObjects
    }
    
    private static func all(satisfying predicate: NSPredicate? = nil, sortedBy sortDescriptors: [NSSortDescriptor]? = nil, in context: NSManagedObjectContext, returnFirstResult: Bool) -> [Self]
    {
        let registeredObjects = context.registeredObjects.lazy.compactMap({ $0 as? Self }).filter({ predicate?.evaluate(with: $0) != false })
        
        if let managedObject = registeredObjects.first, returnFirstResult
        {
            return [managedObject]
        }
        
        let fetchRequest = self.fetchRequest() as! NSFetchRequest<Self>
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        do
        {
            let managedObjects = try context.fetch(fetchRequest)
            
            if let managedObject = managedObjects.first, returnFirstResult
            {
                return [managedObject]
            }
            else
            {
                return managedObjects
            }
        }
        catch
        {
            print("Failed to fetch managed objects.", error)
            return []
        }
    }
}
