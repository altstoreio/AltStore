//
//  ALTApplication+AltStoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 11/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltSign

extension ALTApplication
{
    static let altstoreBundleID = "com.rileytestut.AltStore"
    
    var isAltStoreApp: Bool {
        let isAltStoreApp = self.bundleIdentifier.contains(ALTApplication.altstoreBundleID)
        return isAltStoreApp
    }
    
    func updateExtensionPoints(from oldIdentifier: String, to newIdentifier: String) throws
    {
        guard oldIdentifier != newIdentifier else { return }
        
        func updated(_ identifier: String) -> String
        {
            guard identifier.hasPrefix(oldIdentifier + "."), !identifier.hasPrefix(newIdentifier + ".") else { return identifier }
            return newIdentifier + identifier.dropFirst(oldIdentifier.count)
        }
        
        let directory = self.fileURL.appendingPathComponent("Extensions")
        let fileURLs = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "appexpt"
        {
            guard let extensionPoints = NSDictionary(contentsOf: fileURL) as? [String: Any] else { continue }
            
            let updatedExtensionPoints = Dictionary(extensionPoints.map { (updated($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
            try (updatedExtensionPoints as NSDictionary).write(to: fileURL)
        }
        
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "appex"
        {
            let infoPlistURL = fileURL.appendingPathComponent("Info.plist")
            guard
                let infoDictionary = NSMutableDictionary(contentsOf: infoPlistURL),
                let attributes = (infoDictionary["EXAppExtensionAttributes"] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary,
                let extensionPoint = attributes["EXExtensionPointIdentifier"] as? String,
                updated(extensionPoint) != extensionPoint
            else { continue }
            
            attributes["EXExtensionPointIdentifier"] = updated(extensionPoint)
            infoDictionary["EXAppExtensionAttributes"] = attributes
            try infoDictionary.write(to: infoPlistURL)
        }
    }
}
