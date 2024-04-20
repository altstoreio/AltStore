//
//  ProcessInfo+Device.swift
//  AltServer
//
//  Created by Riley Testut on 9/13/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation
import RegexBuilder

extension ProcessInfo
{
    var deviceModel: String? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer {
            IOObjectRelease(service)
        }
        
        guard 
            let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? Data,
            let cDeviceModel = String(data: modelData, encoding: .utf8)?.cString(using: .utf8) // Remove trailing NULL character
        else { return nil }
        
        let deviceModel = String(cString: cDeviceModel)
        return deviceModel
    }
    
    var operatingSystemBuildVersion: String? {
        let osVersionString = ProcessInfo.processInfo.operatingSystemVersionString
        let buildVersion: String?
        
        if #available(macOS 13, *), let match = osVersionString.firstMatch(of: Regex {
            "(Build "
            Capture {
                OneOrMore(.anyNonNewline)
            }
            ")"
        })
        {
            buildVersion = String(match.1)
        }
        else if let build = osVersionString.split(separator: " ").last?.dropLast()
        {
            buildVersion = String(build)
        }
        else
        {
            buildVersion = nil
        }
        
        return buildVersion
    }
}
