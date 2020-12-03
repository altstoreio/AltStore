//
//  main.swift
//  AltXPC
//
//  Created by Riley Testut on 12/3/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

class ServiceDelegate : NSObject, NSXPCListenerDelegate
{
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool
    {
        newConnection.exportedInterface = NSXPCInterface(with: AltXPCProtocol.self)

        let exportedObject = AltXPC()
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let serviceDelegate = ServiceDelegate()

let listener = NSXPCListener.service()
listener.delegate = serviceDelegate
listener.resume()

RunLoop.main.run()

