//
//  EnableJITIntentHandler.swift
//  AltStore
//
//  Created by Jhonatan A. on 11/11/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import Intents

@available(iOS 14, *)
class EnableJITIntentHandler: NSObject, EnableJITIntentHandling
{
    public func provideAppOptionsCollection(for intent: EnableJITIntent, with completion: @escaping (INObjectCollection<App>?, Error?) -> Void)
    {
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                print("Error starting extension:", error)
            }
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let apps = InstalledApp.all(in: context).map { (installedApp) in
                    return App(identifier: installedApp.bundleIdentifier, display: installedApp.name)
                }
                
                let collection = INObjectCollection(items: apps)
                completion(collection, nil)
            }
        }
    }
    
    func handle(intent: EnableJITIntent, completion: @escaping (EnableJITIntentResponse) -> Void)
    {
        guard let requestedAppBundleIdentifier = intent.app?.identifier else {
            completion(EnableJITIntentResponse(code: .failure, userActivity: nil))
            return
        }
        
        DatabaseManager.shared.start { (error) in
            if let _ = error
            {
                completion(EnableJITIntentResponse(code: .failure, userActivity: nil))
                return
            }
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), requestedAppBundleIdentifier)
                guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else {
                    completion(EnableJITIntentResponse(code: .failure, userActivity: nil))
                    return
                }
                
                AppManager.shared.enableJIT(for: installedApp) { result in
                    DispatchQueue.main.async {
                        switch result
                        {
                        case .success:
                            completion(EnableJITIntentResponse(code: .success, userActivity: nil))
                        case .failure( _):
                            completion(EnableJITIntentResponse(code: .failure, userActivity: nil))
                        }
                    }
                }
            }
        }
    }
}
