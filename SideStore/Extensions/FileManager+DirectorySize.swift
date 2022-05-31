//
//  FileManager+DirectorySize.swift
//  AltStore
//
//  Created by Riley Testut on 3/31/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

extension FileManager
{
    func directorySize(at directoryURL: URL) -> Int?
    {
        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        
        var total: Int = 0
        
        for case let fileURL as URL in enumerator
        {
            do
            {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                guard let fileSize = resourceValues.fileSize else { continue }
                
                total += fileSize
            }
            catch
            {
                print("Failed to read file size for item: \(fileURL).", error)
            }
        }
        
        return total
    }
}
