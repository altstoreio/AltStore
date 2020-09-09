//
//  Benefit.swift
//  AltStore
//
//  Created by Riley Testut on 8/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension PatreonAPI
{
    struct BenefitResponse: Decodable
    {
        var id: String
    }
}

public struct Benefit: Hashable
{
    public var type: ALTPatreonBenefitType
    
    init(response: PatreonAPI.BenefitResponse)
    {
        self.type = ALTPatreonBenefitType(response.id)
    }
}
