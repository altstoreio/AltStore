//
//  main.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

autoreleasepool {
    DaemonConnectionManager.shared.start()
    RunLoop.current.run()
}
