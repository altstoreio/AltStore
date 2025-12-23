//
//  Federatable.swift
//  AltStoreCore
//
//  Created by Riley Testut on 8/25/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

public protocol Federatable
{
    var statusID: String? { get set }
    var federatedURL: URL? { get set }
    
    var likesCount: Int32 { get set }
    var boostsCount: Int32 { get set }
    var commentsCount: Int32 { get set }
}

extension Federatable
{
    public typealias Mock = __MockFederatable
}

public struct __MockFederatable: Federatable
{
    public var statusID: String?
    public var federatedURL: URL?
    
    public var likesCount: Int32
    public var boostsCount: Int32
    public var commentsCount: Int32
    
    public init(statusID: String? = nil, federatedURL: URL? = nil, likesCount: Int32 = 0, boostsCount: Int32 = 0, commentsCount: Int32 = 0)
    {
        self.statusID = statusID
        self.federatedURL = federatedURL
        self.likesCount = likesCount
        self.boostsCount = boostsCount
        self.commentsCount = commentsCount
    }
}
