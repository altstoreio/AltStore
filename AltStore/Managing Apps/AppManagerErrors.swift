//
//  AppManagerErrors.swift
//  AltStore
//
//  Created by Riley Testut on 8/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltStoreCore

extension AppManager
{
    struct FetchSourcesError: LocalizedError, CustomNSError
    {
        var primaryError: Error?
        
        var sources: Set<Source>?
        var errors = [Source: Error]()
        
        var managedObjectContext: NSManagedObjectContext?
        
        var errorDescription: String? {
            if let error = self.primaryError
            {
                return error.localizedDescription
            }
            else
            {
                var localizedDescription: String?
                
                self.managedObjectContext?.performAndWait {
                    if self.sources?.count == 1
                    {
                        localizedDescription = NSLocalizedString("Could not refresh store.", comment: "")
                    }
                    else if self.errors.count == 1
                    {
                        guard let source = self.errors.keys.first else { return }
                        localizedDescription = String(format: NSLocalizedString("Could not refresh source “%@”.", comment: ""), source.name)
                    }
                    else
                    {
                        localizedDescription = String(format: NSLocalizedString("Could not refresh %@ sources.", comment: ""), NSNumber(value: self.errors.count))
                    }
                }
                
                return localizedDescription
            }
        }
        
        var recoverySuggestion: String? {
            if let error = self.primaryError as NSError?
            {
                return error.localizedRecoverySuggestion
            }
            else if self.errors.count == 1
            {
                return nil
            }
            else
            {
                return NSLocalizedString("Tap to view source errors.", comment: "")
            }
        }
        
        var errorUserInfo: [String : Any] {
            guard let error = self.errors.values.first, self.errors.count == 1 else { return [:] }
            return [NSUnderlyingErrorKey: error]
        }
        
        init(_ error: Error)
        {
            self.primaryError = error
        }
        
        init(sources: Set<Source>, errors: [Source: Error], context: NSManagedObjectContext)
        {
            self.sources = sources
            self.errors = errors
            self.managedObjectContext = context
        }
    }
}
