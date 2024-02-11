//
//  ALTServerError+Conveniences.swift
//  AltKit
//
//  Created by Riley Testut on 6/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

public extension ALTServerError
{
    init<E: Error>(_ error: E)
    {
        switch error
        {
        case let error as ALTServerError: self = error
        case let error as ALTServerConnectionError: self = ALTServerError(.connectionFailed, underlyingError: error)
        case let error as ALTAppleAPIError where error.code == .invalidAnisetteData: self = ALTServerError(.invalidAnisetteData, underlyingError: error)
        case is DecodingError: self = ALTServerError(.invalidRequest, underlyingError: error)
        case is EncodingError: self = ALTServerError(.invalidResponse, underlyingError: error)
        case let error as NSError:
            // Assign error as underlying error, even if there already is one,
            // because it'll still be accessible via error.underlyingError.underlyingError.
            var userInfo = error.userInfo
            userInfo[NSUnderlyingErrorKey] = error
            
            self = ALTServerError(.underlyingError, userInfo: userInfo)
        }
    }
    
    init<E: Error>(_ code: ALTServerError.Code, underlyingError: E)
    {
        self = ALTServerError(code, userInfo: [NSUnderlyingErrorKey: underlyingError])
    }
}
