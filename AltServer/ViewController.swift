//
//  ViewController.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad()
    {
        super.viewDidLoad()
    }
}

private extension ViewController
{
    @IBAction func listConnectedDevices(_ sender: NSButton)
    {
        let devices = ALTDeviceManager.shared.connectedDevices
        print(devices)
    }
}
