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
    case developer
    case entertainment
    case games
    case lifestyle
    case photoAndVideo = "photo"
    case social
    case utilities
    case other
    
    public var localizedName: String {
        switch self
        {
        case .developer: NSLocalizedString("Developer", comment: "")
        case .entertainment: NSLocalizedString("Entertainment", comment: "")
        case .games: NSLocalizedString("Games", comment: "")
        case .lifestyle: NSLocalizedString("Lifestyle", comment: "")
        case .photoAndVideo: NSLocalizedString("Photo & Video", comment: "")
        case .social: NSLocalizedString("Social", comment: "")
        case .utilities: NSLocalizedString("Utilities", comment: "")
        case .other: NSLocalizedString("Other", comment: "")
        }
    }
    
    public var symbolName: String {
        switch self
        {
        case .developer: "hammer"
        case .entertainment: "popcorn"
        case .games: "gamecontroller"
        case .lifestyle: "chair.lounge"
        case .photoAndVideo: "camera"
        case .social: "hand.wave"
        case .utilities: "paperclip"
        case .other: "bag.badge.questionmark"
        }
    }
    
    public var filledSymbolName: String {
        switch self
        {
        case .developer: "hammer.fill"
        case .entertainment: "popcorn.fill"
        case .games: "gamecontroller.fill"
        case .lifestyle: "chair.lounge.fill"
        case .photoAndVideo: "camera.fill"
        case .social: "hand.wave.fill"
        case .utilities: "paperclip"
        case .other: "bag.fill.badge.questionmark"
        }
    }
    
    public var tintColor: UIColor {
        switch self
        {
        case .developer: UIColor.systemPurple
        case .entertainment: UIColor.systemPink
        case .games: UIColor.systemGreen
        case .lifestyle: UIColor.systemYellow
        case .photoAndVideo: UIColor.systemGray
        case .social: UIColor.systemRed
        case .utilities: UIColor.systemBlue
        case .other: UIColor.black
        }
    }
}
