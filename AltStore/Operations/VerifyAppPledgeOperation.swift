//
//  VerifyAppPledgeOperation.swift
//  AltStore
//
//  Created by Riley Testut on 10/30/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltStoreCore

protocol VerifyAppPledgeContext
{
    // @AsyncManaged
    var storeApp: StoreApp? { get }
}

class VerifyAppPledgeOperation<Context: VerifyAppPledgeContext>: ResultOperation<Void>
{
    let context: Context
    
    init(context: Context)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        Task<Void, Never>.detached(priority: .userInitiated) {
            do
            {
                guard let storeApp = self.context.storeApp, let managedObjectContext = storeApp.managedObjectContext else { throw OperationError.invalidParameters }
                
                let (appName, isPledged, isPledgeRequired) = await managedObjectContext.performAsync({ (storeApp.name, storeApp.isPledged, storeApp.isPledgeRequired) })
                guard isPledgeRequired else { return self.finish(.success(())) }
                
                do
                {
                    if !PatreonAPI.shared.isAuthenticated
                    {
                        throw OperationError.pledgeRequired(appName: appName)
                    }
                    
                    if isPledgeRequired && !isPledged
                    {
                        throw OperationError.pledgeRequired(appName: appName)
                    }
                }
                catch let error as OperationError where error.code == .pledgeRequired
                {
                    guard await managedObjectContext.performAsync({ storeApp.installedApp != nil }) else { throw error }
                    
                    // Assume if there is an InstalledApp, the user had previously pledged to this app.
                    throw OperationError.pledgeInactive(appName: appName)
                }
                
                return self.finish(.success(()))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}
