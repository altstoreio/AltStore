//
//  RefreshAttempt.swift
//  AltStore
//
//  Created by Riley Testut on 7/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

@objc(RefreshAttempt)
class RefreshAttempt: NSManagedObject, Fetchable
{
    @NSManaged var identifier: String
    @NSManaged var date: Date
    
    @NSManaged var isSuccess: Bool
    @NSManaged var errorDescription: String?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init<T>(identifier: String, result: Result<T, Error>, context: NSManagedObjectContext)
    {
        super.init(entity: RefreshAttempt.entity(), insertInto: context)
        
        self.identifier = identifier
        self.date = Date()
        
        switch result
        {
        case .success:
            self.isSuccess = true
            self.errorDescription = nil
            
        case .failure(let error):
            self.isSuccess = false
            self.errorDescription = error.localizedDescription
        }
    }
}

extension RefreshAttempt
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<RefreshAttempt>
    {
        return NSFetchRequest<RefreshAttempt>(entityName: "RefreshAttempt")
    }
}
