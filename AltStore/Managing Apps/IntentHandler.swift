//
//  IntentHandler.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

class IntentHandler: NSObject, RefreshAllIntentHandling
{
    func handle(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)
    {
        func refreshApps()
        {
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let installedApps = InstalledApp.fetchActiveApps(in: context)
                AppManager.shared.backgroundRefresh(installedApps) { (result) in
                    do
                    {
                        let results = try result.get()
                        
                        for (_, result) in results
                        {
                            guard case let .failure(error) = result else { continue }
                            throw error
                        }
                        
                        completion(RefreshAllIntentResponse(code: .success, userActivity: nil))
                    }
                    catch RefreshError.noInstalledApps
                    {
                        completion(RefreshAllIntentResponse(code: .success, userActivity: nil))
                    }
                    catch let error as NSError
                    {
                        print("Failed to refresh apps in background.", error)
                        completion(RefreshAllIntentResponse.failure(localizedDescription: error.localizedFailureReason ?? error.localizedDescription))
                    }
                }
            }
        }
        
        if !DatabaseManager.shared.isStarted
        {
            DatabaseManager.shared.start() { (error) in
                if let error = error
                {
                    completion(RefreshAllIntentResponse.failure(localizedDescription: error.localizedDescription))
                }
                else
                {
                    refreshApps()
                }
            }
        }
        else
        {
            refreshApps()
        }
    }
}
