//
//  ProcessInfo+Previews.swift
//  AltStoreCore
//
//  Created by Riley Testut on 10/11/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

public extension ProcessInfo
{
    var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
