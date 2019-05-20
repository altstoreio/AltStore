//
//  DatabaseManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

import Roxas

public class DatabaseManager
{
    public static let shared = DatabaseManager()
    
    public let persistentContainer: RSTPersistentContainer
    
    public private(set) var isStarted = false
    
    private init()
    {
        self.persistentContainer = RSTPersistentContainer(name: "AltStore")
    }
}

public extension DatabaseManager
{
    func start(completionHandler: @escaping (Error?) -> Void)
    {
        guard !self.isStarted else { return completionHandler(nil) }
        
        self.persistentContainer.loadPersistentStores { (description, error) in
            guard error == nil else { return completionHandler(error!) }
            
            self.isStarted = true
            
            completionHandler(error)
        }
    }
}

public extension DatabaseManager
{
    var viewContext: NSManagedObjectContext {
        return self.persistentContainer.viewContext
    }
}
