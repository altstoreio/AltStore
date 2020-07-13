//
//  IntentHandler.swift
//  IntentHandler
//
//  Created by Riley Testut on 7/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Intents
import AltStoreCore

class IntentHandler: INExtension, ViewAppIntentHandling {
    
    public func provideAppOptionsCollection(for intent: ViewAppIntent, with completion: @escaping (INObjectCollection<App>?, Error?) -> Void)
    {
        print("Providing options...")
        
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
    
    override func handler(for intent: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.
        
        return self
    }
    
}
