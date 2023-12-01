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
    typealias CampaignResponse = DataResponse<CampaignAttributes, AnyRelationships>
    
    struct CampaignAttributes: Decodable
    {
        var url: URL
    }
}

extension PatreonAPI
{
    public struct Campaign
    {
        public var identifier: String
        public var url: URL
        
        internal init(response: PatreonAPI.CampaignResponse)
        {
            self.identifier = response.id
            self.url = response.attributes.url
        }
    }
}
