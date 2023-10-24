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
        struct Attributes: Decodable
        {
            var url: URL
        }
        
        var id: String
        var attributes: Attributes
    }
}

public struct Campaign
{
    public var identifier: String
    public var url: URL?
        
    init(response: PatreonAPI.CampaignResponse)
    {
        self.identifier = response.id
        self.url = response.attributes.url
    }
}
