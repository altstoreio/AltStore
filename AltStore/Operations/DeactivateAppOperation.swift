//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas
import minimuxer

@objc(DeactivateAppOperation)
class DeactivateAppOperation: ResultOperation<InstalledApp>
{
    let app: InstalledApp
    let context: OperationContext
    
    init(app: InstalledApp, context: OperationContext)
    {
        self.app = app
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
        
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let installedApp = context.object(with: self.app.objectID) as! InstalledApp
            let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
            let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles
            
            for profile in allIdentifiers {
                do {
                    let res = try remove_provisioning_profile(id: profile)
                    if case Uhoh.Bad(let code) = res {
                        self.finish(.failure(minimuxer_to_operation(code: code)))
                    }
                } catch Uhoh.Bad(let code) {
                    self.finish(.failure(minimuxer_to_operation(code: code)))
                } catch {
                    self.finish(.failure(ALTServerError(.unknownResponse)))
                }
            }
            
            self.progress.completedUnitCount += 1
            installedApp.isActive = false
            self.finish(.success(installedApp))
        }
    }
}
