//
//  Tier.swift
//  AltStore
//
//  Created by Riley Testut on 8/21/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension PatreonAPI
{
    typealias TierResponse = DataResponse<TierAttributes, TierRelationships>
    
    struct TierAttributes: Decodable
    {
        var title: String
    }
    
    struct TierRelationships: Decodable
    {
        var benefits: Response<[AnyItemResponse]>?
    }
}

extension PatreonAPI
{
    public struct Tier: Hashable
    {
        public var name: String
        public var identifier: String
        
        // Relationships
        public var benefits: [Benefit] = []
        
        internal init(response: TierResponse, including included: IncludedResponses?)
        {
            self.name = response.attributes.title
            self.identifier = response.id
            
            guard let included, let benefitIDs = response.relationships?.benefits?.data.map(\.id) else { return }
            
            let benefits = benefitIDs.compactMap { included.benefits[$0] }.map(Benefit.init(response:))
            self.benefits = benefits
        }
    }
}
