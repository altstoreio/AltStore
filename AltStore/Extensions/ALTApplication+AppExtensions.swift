//
//  ALTApplication+AppExtensions.swift
//  AltStore
//
//  Created by Riley Testut on 2/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import AltSign

extension ALTApplication
{
    var appExtensions: Set<ALTApplication> {
        guard let bundle = Bundle(url: self.fileURL) else { return [] }
        
        var appExtensions: Set<ALTApplication> = []
        
        if let directory = bundle.builtInPlugInsURL, let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
        {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "appex"
            {
                guard let appExtension = ALTApplication(fileURL: fileURL) else { continue }
                appExtensions.insert(appExtension)
            }
        }
        
        return appExtensions
    }
}
