//
//  ALTWrappedError.swift
//  AltStore
//
//  Created by Riley Testut on 10/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation

public class ALTWrappedError: NSError
{
    public let wrappedError: Error
    
    private var wrappedNSError: NSError {
        self.wrappedError as NSError
    }
    
    public init(error: Error, userInfo: [String: Any])
    {
        self.wrappedError = error
        
        super.init(domain: error._domain, code: error._code, userInfo: userInfo)
    }
    
    public required init?(coder: NSCoder)
    {
        fatalError("ALTWrappedError does not support NSCoding.")
    }
    
    override public var localizedDescription: String {
        if let localizedFailure = self.userInfo[NSLocalizedFailureErrorKey] as? String
        {
            let localizedFailureReason = self.wrappedNSError.localizedFailureReason ?? self.wrappedError.localizedDescription
            
            let localizedDescription = localizedFailure + " " + localizedFailureReason
            return localizedDescription
        }
        
        // localizedFailure is nil, so return wrappedError's localizedDescription.
        return self.wrappedError.localizedDescription
    }
    
    override public var localizedFailureReason: String? {
        return self.wrappedNSError.localizedFailureReason
    }
    
    override public var localizedRecoverySuggestion: String? {
        return self.wrappedNSError.localizedRecoverySuggestion
    }
    
    override public var debugDescription: String {
        return self.wrappedNSError.debugDescription
    }
    
    override public var helpAnchor: String? {
        return self.wrappedNSError.helpAnchor
    }
}
