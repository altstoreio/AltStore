//
//  StoreCategory.swift
//  AltStoreCore
//
//  Created by Riley Testut on 11/8/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import UIKit

public enum StoreCategory: String, CaseIterable
{
    case other = "Other"
    case utilities = "Utilities"
    case developer = "Developer"
    case games = "Games"
    case entertainment = "Entertainment"
    
    public var localizedName: String {
        switch self
        {
        case .other: return NSLocalizedString("Other", comment: "")
        case .utilities: return NSLocalizedString("Utilities", comment: "")
        case .developer: return NSLocalizedString("Developer", comment: "")
        case .games: return NSLocalizedString("Games", comment: "")
        case .entertainment: return NSLocalizedString("Entertainment", comment: "")
        }
    }
    
    public var symbolName: String {
        switch self
        {
        case .utilities: return "paperclip"
        case .developer: return "hammer"
        case .games: return "gamecontroller"
        case .entertainment: return "tv"
        case .other: return "bag.badge.questionmark"
        }
    }
    
    public var filledSymbolName: String {
        switch self
        {
        case .utilities: return "paperclip"
        case .developer: return "hammer.fill"
        case .games: return "gamecontroller.fill"
        case .entertainment: return "tv.fill"
        case .other: return "bag.fill.badge.questionmark"
        }
    }
    
    public var tintColor: UIColor {
        switch self
        {
        case .utilities: return .systemBlue
        case .developer: return .systemPurple
        case .games: return .systemGreen
        case .entertainment: return .systemPink
        case .other: return .black
        }
    }
}
