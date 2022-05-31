//
//  INInteraction+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 9/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Intents

// Requires iOS 14 in-app intent handling.
@available(iOS 14, *)
extension INInteraction
{
    static func refreshAllApps() -> INInteraction
    {
        let refreshAllIntent = RefreshAllIntent()
        refreshAllIntent.suggestedInvocationPhrase = NSString.deferredLocalizedIntentsString(with: "Refresh my apps") as String
        
        let interaction = INInteraction(intent: refreshAllIntent, response: nil)
        return interaction
    }
}
