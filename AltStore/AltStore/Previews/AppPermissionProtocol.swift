//
//  AppPermissionProtocol.swift
//  AltStore
//
//  Created by Riley Testut on 5/23/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltStoreCore

@dynamicMemberLookup
protocol AppPermissionProtocol: Hashable
{
    var permission: any ALTAppPermission { get }
    var usageDescription: String? { get }
    
    subscript<T>(dynamicMember dynamicMember: KeyPath<any ALTAppPermission, T>) -> T { get }
}

extension AppPermission: AppPermissionProtocol {}

struct PreviewAppPermission: AppPermissionProtocol
{
    var permission: any ALTAppPermission
    var usageDescription: String? { "Allows Delta to use images from your Photo Library as game artwork." }
    
    subscript<T>(dynamicMember dynamicMember: KeyPath<any ALTAppPermission, T>) -> T
    {
        return self.permission[keyPath: dynamicMember]
    }
}

extension PreviewAppPermission
{
    static func ==(lhs: PreviewAppPermission, rhs: PreviewAppPermission) -> Bool
    {
        return lhs.permission.isEqual(rhs.permission)
    }
    
    func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.permission)
    }
}
