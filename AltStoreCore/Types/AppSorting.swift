//
//  AppSorting.swift
//  AltStoreCore
//
//  Created by Riley Testut on 11/14/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

@objc public enum AppSortOrder: Int, CaseIterable
{
    case ascending = 0
    case descending = 1
}

public enum AppSorting: String, CaseIterable
{
    case `default`
    case name
    case developer
    case lastUpdated
    
    public var localizedName: String {
        switch self
        {
        case .default: return NSLocalizedString("Default", comment: "")
        case .name: return NSLocalizedString("Name", comment: "")
        case .developer: return NSLocalizedString("Developer", comment: "")
        case .lastUpdated: return NSLocalizedString("Last Updated", comment: "")
        }
    }
    
    public var defaultSortOrder: AppSortOrder {
        switch self
        {
        case .name, .developer, .default: return .ascending
        case .lastUpdated: return .descending
        }
    }
}
