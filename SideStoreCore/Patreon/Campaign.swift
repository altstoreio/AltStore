//
//  Campaign.swift
//  AltStore
//
//  Created by Riley Testut on 8/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension PatreonAPI
{
    struct CampaignResponse: Decodable
    {
        var id: String
    }
}

public struct Campaign
{
    public var identifier: String
        
    init(response: PatreonAPI.CampaignResponse)
    {
        self.identifier = response.id
    }
}
