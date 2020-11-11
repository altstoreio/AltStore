//
//  IntentHandler.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

@available(iOS 14, *)
class IntentHandler: NSObject, RefreshAllIntentHandling
{
    private let queue = DispatchQueue(label: "io.altstore.IntentHandler")
    
    private var completionHandlers = [RefreshAllIntent: (RefreshAllIntentResponse) -> Void]()
    private var queuedResponses = [RefreshAllIntent: RefreshAllIntentResponse]()
    
    func confirm(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)
    {
        // Refreshing apps usually, but not always, completes within alotted time.
        // As a workaround, we'll start refreshing apps in confirm() so we can
        // take advantage of some extra time before starting handle() timeout timer.

        self.completionHandlers[intent] = { (response) in
            if response.code != .ready
            {
                // Operation finished before confirmation "timeout".
                // Cache response to return it when handle() is called.
                self.queuedResponses[intent] = response
            }
            
            completion(RefreshAllIntentResponse(code: .ready, userActivity: nil))
        }
        
        // Give ourselves 9 extra seconds before starting handle() timeout timer.
        // 10 seconds or longer results in timeout regardless.
        self.queue.asyncAfter(deadline: .now() + 9.0) {
            self.finish(intent, response: RefreshAllIntentResponse(code: .ready, userActivity: nil))
        }
        
        if !DatabaseManager.shared.isStarted
        {
            DatabaseManager.shared.start() { (error) in
                if let error = error
                {
                    self.finish(intent, response: RefreshAllIntentResponse.failure(localizedDescription: error.localizedDescription))
                }
                else
                {
                    self.refreshApps(intent: intent)
                }
            }
        }
        else
        {
            self.refreshApps(intent: intent)
        }
    }
    
    func handle(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)
    {
        self.completionHandlers[intent] = { (response) in
            // Ignore .ready response from confirm() timeout.
            guard response.code != .ready else { return }
            completion(response)
        }

        if let response = self.queuedResponses[intent]
        {
            self.queuedResponses[intent] = nil
            self.finish(intent, response: response)
        }
    }
}

@available(iOS 14, *)
private extension IntentHandler
{
    func finish(_ intent: RefreshAllIntent, response: RefreshAllIntentResponse)
    {
        self.queue.async {
            guard let completionHandler = self.completionHandlers[intent] else { return }
            self.completionHandlers[intent] = nil
            
            completionHandler(response)
        }
    }
    
    func refreshApps(intent: RefreshAllIntent)
    {
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let installedApps = InstalledApp.fetchActiveApps(in: context)
            AppManager.shared.backgroundRefresh(installedApps, presentsNotifications: false) { (result) in
                do
                {
                    let results = try result.get()
                    
                    for (_, result) in results
                    {
                        guard case let .failure(error) = result else { continue }
                        throw error
                    }
                    
                    self.finish(intent, response: RefreshAllIntentResponse(code: .success, userActivity: nil))
                }
                catch RefreshError.noInstalledApps
                {
                    self.finish(intent, response: RefreshAllIntentResponse(code: .success, userActivity: nil))
                }
                catch let error as NSError
                {
                    print("Failed to refresh apps in background.", error)
                    self.finish(intent, response: RefreshAllIntentResponse.failure(localizedDescription: error.localizedFailureReason ?? error.localizedDescription))
                }
            }
        }
    }
}
