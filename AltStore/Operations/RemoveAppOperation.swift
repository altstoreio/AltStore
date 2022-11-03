//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import minimuxer

@objc(RemoveAppOperation)
class RemoveAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        installedApp.managedObjectContext?.perform {
            let resignedBundleIdentifier = installedApp.resignedBundleIdentifier
            
            do {
                let res = try remove_app(app_id: resignedBundleIdentifier)
                if case Uhoh.Bad(let code) = res {
                    self.finish(.failure(minimuxer_to_operation(code: code)))
                }
            } catch Uhoh.Bad(let code) {
                self.finish(.failure(minimuxer_to_operation(code: code)))
            } catch {
                self.finish(.failure(ALTServerError(.appDeletionFailed)))
            }
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                self.progress.completedUnitCount += 1
                
                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                installedApp.isActive = false
                self.finish(.success(installedApp))
            }
        }
    }
}

