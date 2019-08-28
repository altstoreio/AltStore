//
//  Patron.swift
//  AltStore
//
//  Created by Riley Testut on 8/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension PatreonAPI
{
    struct PatronResponse: Decodable
    {
        struct Attributes: Decodable
        {
            var full_name: String
            var patron_status: String
        }
        
        struct Relationships: Decodable
        {
            struct Tiers: Decodable
            {
                struct TierID: Decodable
                {
                    var id: String
                    var type: String
                }
                
                var data: [TierID]
            }
            
            var currently_entitled_tiers: Tiers
        }
        
        var id: String
        var attributes: Attributes
        
        var relationships: Relationships?
    }
}

extension Patron
{
    enum Status: String, Decodable
    {
        case active = "active_patron"
        case declined = "declined_patron"
        case former = "former_patron"
    }
}

class Patron
{
    var name: String
    var identifier: String
    
    var status: Status
    
    var benefits: Set<Benefit> = []
    
    init(response: PatreonAPI.PatronResponse)
    {
        self.name = response.attributes.full_name
        self.identifier = response.id
        self.status = Status(rawValue: response.attributes.patron_status) ?? .former
    }
}
