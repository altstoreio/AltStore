//
//  PatreonAPI+Responses.swift
//  AltStoreCore
//
//  Created by Riley Testut on 11/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

protocol ResponseData: Decodable
{
}

// Allows us to use Arrays with Response<> despite them not conforming to `ItemResponse`
extension Array: ResponseData where Element: ItemResponse
{
}

protocol ItemResponse: ResponseData
{
    var id: String { get }
    var type: String { get }
}

extension PatreonAPI
{
    struct Response<Data: ResponseData>: Decodable
    {
        var data: Data
        
        var included: IncludedResponses?
        var links: [String: URL]?
    }
    
    struct AnyItemResponse: ItemResponse
    {
        var id: String
        var type: String
    }
    
    struct DataResponse<Attributes: Decodable, Relationships: Decodable>: ItemResponse
    {
        var id: String
        var type: String
        
        var attributes: Attributes
        var relationships: Relationships?
    }
    
    // `Never` only conforms to Decodable from iOS 17 onwards,
    // so use our own "Empty" type for DataResponses without relationships.
    struct AnyRelationships: Decodable
    {
    }
    
    struct IncludedResponses: Decodable
    {
        var items: [IncludedItem]
        
        var campaigns: [String: CampaignResponse]
        var patrons: [String: PatronResponse]
        var tiers: [String: TierResponse]
        var benefits: [String: BenefitResponse]
        
        init(from decoder: Decoder) throws
        {
            let container = try decoder.singleValueContainer()
            self.items = try container.decode([IncludedItem].self)
            
            var campaignsByID = [String: PatreonAPI.CampaignResponse]()
            var patronsByID = [String: PatreonAPI.PatronResponse]()
            var tiersByID = [String: PatreonAPI.TierResponse]()
            var benefitsByID = [String: PatreonAPI.BenefitResponse]()
            
            for response in self.items
            {
                switch response
                {
                case .campaign(let response): campaignsByID[response.id] = response
                case .patron(let response): patronsByID[response.id] = response
                case .tier(let response): tiersByID[response.id] = response
                case .benefit(let response): benefitsByID[response.id] = response
                case .unknown: break // Ignore
                }
            }
            
            self.campaigns = campaignsByID
            self.patrons = patronsByID
            self.tiers = tiersByID
            self.benefits = benefitsByID
        }
    }
    
    enum IncludedItem: ItemResponse
    {
        case tier(TierResponse)
        case benefit(BenefitResponse)
        case patron(PatronResponse)
        case campaign(CampaignResponse)
        case unknown(AnyItemResponse)
        
        var id: String {
            switch self
            {
            case .tier(let response): return response.id
            case .benefit(let response): return response.id
            case .patron(let response): return response.id
            case .campaign(let response): return response.id
            case .unknown(let response): return response.id
            }
        }
        
        var type: String {
            switch self
            {
            case .tier(let response): return response.type
            case .benefit(let response): return response.type
            case .patron(let response): return response.type
            case .campaign(let response): return response.type
            case .unknown(let response): return response.type
            }
        }
        
        private enum CodingKeys: String, CodingKey
        {
            case type
        }
        
        init(from decoder: Decoder) throws
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            let type = try container.decode(String.self, forKey: .type)
            switch type
            {
            case "tier":
                let response = try TierResponse(from: decoder)
                self = .tier(response)
                
            case "benefit":
                let response = try BenefitResponse(from: decoder)
                self = .benefit(response)
                
            case "member":
                let response = try PatronResponse(from: decoder)
                self = .patron(response)
                
            case "campaign":
                let response = try CampaignResponse(from: decoder)
                self = .campaign(response)
                
            default:
                Logger.main.error("Unrecognized PatreonAPI response type: \(type, privacy: .public).")
                
                let response = try AnyItemResponse(from: decoder)
                self = .unknown(response)
            }
        }
    }
}
