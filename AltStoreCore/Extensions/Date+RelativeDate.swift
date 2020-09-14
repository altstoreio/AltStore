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
    func numberOfCalendarDays(since date: Date) -> Int
    {
        let today = Calendar.current.startOfDay(for: self)
        let previousDay = Calendar.current.startOfDay(for: date)
        
        let components = Calendar.current.dateComponents([.day], from: previousDay, to: today)
        return components.day!
    }
    
    func relativeDateString(since date: Date, dateFormatter: DateFormatter) -> String
    {
        let numberOfDays = self.numberOfCalendarDays(since: date)
        
        switch numberOfDays
        {
        case 0: return NSLocalizedString("Today", comment: "")
        case 1: return NSLocalizedString("Yesterday", comment: "")
        case 2...7: return String(format: NSLocalizedString("%@ days ago", comment: ""), NSNumber(value: numberOfDays))
        default: return dateFormatter.string(from: date)
        }
    }
}
