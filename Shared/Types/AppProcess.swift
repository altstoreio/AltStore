//
//  AppProcess.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

enum AppProcess: CustomStringConvertible
{
    case name(String)
    case pid(Int)
    
    var description: String {
        switch self
        {
        case .name(let name): return name
        case .pid(let pid): return "Process \(pid)"
        }
    }
    
    init(_ value: String)
    {
        if let pid = Int(value)
        {
            self = .pid(pid)
        }
        else
        {
            self = .name(value)
        }
    }
}
