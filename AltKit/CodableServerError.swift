//
//  CodableServerError.swift
//  AltKit
//
//  Created by Riley Testut on 3/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

// Can only automatically conform ALTServerError.Code to Codable, not ALTServerError itself
extension ALTServerError.Code: Codable {}

struct CodableServerError: Codable
{
    var error: ALTServerError {
        return ALTServerError(self.errorCode, userInfo: self.userInfo ?? [:])
    }
    
    private var errorCode: ALTServerError.Code
    private var userInfo: [String: String]?
    
    private enum CodingKeys: String, CodingKey
    {
        case errorCode
        case userInfo
    }

    init(error: ALTServerError)
    {
        self.errorCode = error.code
        
        let userInfo = error.userInfo.compactMapValues { $0 as? String }
        if !userInfo.isEmpty
        {
            self.userInfo = userInfo
        }
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let errorCode = try container.decode(Int.self, forKey: .errorCode)
        self.errorCode = ALTServerError.Code(rawValue: errorCode) ?? .unknown
        
        let userInfo = try container.decodeIfPresent([String: String].self, forKey: .userInfo)
        self.userInfo = userInfo
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.error.code.rawValue, forKey: .errorCode)
        try container.encodeIfPresent(self.userInfo, forKey: .userInfo)
    }
}

