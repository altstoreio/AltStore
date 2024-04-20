//
//  Date+RelativeDate.swift
//  AltStore
//
//  Created by Riley Testut on 7/28/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

public extension Date
{
    static let shortDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    static let mediumDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    func numberOfCalendarDays(since date: Date) -> Int
    {
        let today = Calendar.current.startOfDay(for: self)
        let previousDay = Calendar.current.startOfDay(for: date)
        
        let components = Calendar.current.dateComponents([.day], from: previousDay, to: today)
        return components.day!
    }
    
    func relativeDateString(since date: Date, dateFormatter: DateFormatter? = nil) -> String
    {
        let dateFormatter = dateFormatter ?? Date.mediumDateFormatter
        let numberOfDays = self.numberOfCalendarDays(since: date)
        
        switch numberOfDays
        {
        case 0: return NSLocalizedString("Today", comment: "")
        case 1: return NSLocalizedString("Yesterday", comment: "")
        default: return dateFormatter.string(from: date)
        }
    }
}
