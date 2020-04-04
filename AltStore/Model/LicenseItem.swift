//
//  LicenseItem.swift
//  AltStore
//
//  Created by Kevin Romero Peces-Barba on 04/04/2020.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

struct LicenseItem: Decodable {
    let product: String
    let author: String
    let copyright: String
    let license: String
}
