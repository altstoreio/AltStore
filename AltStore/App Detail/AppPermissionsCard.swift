//
//  AppPermissionsCard.swift
//  AltStore
//
//  Created by Riley Testut on 5/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore

@available(iOS 16, *)
extension AppPermissionsCard
{
    struct PermissionKey: Hashable
    {
        var key: String
        var permission: any ALTAppPermission
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(self.key)
            hasher.combine(self.permission)
        }
        
        static func ==(lhs: PermissionKey, rhs: PermissionKey) -> Bool
        {
            let isEqual = lhs.key == rhs.key && lhs.permission.isEqual(to: rhs.permission)
            return isEqual
        }
    }
}

protocol AppPermissionProtocol: Identifiable
{
    var localizedName: String { get }
    var permission: any ALTAppPermission { get }
    
    var usageDescription: String? { get }
}

extension AppPermission: AppPermissionProtocol {}

struct AppPermission_Preview: AppPermissionProtocol
{
    var localizedName: String
    var permission: any ALTAppPermission
    
    var id: String {
        return self.permission.rawValue
    }
    
    var usageDescription: String? { "Allows Delta to use images from your Photo Library as game artwork." }
}

@available(iOS 16, *)
struct AppPermissionsCard<Permission: AppPermissionProtocol>: View
{
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
    let tintColor: Color
    
    @State
    var permissions: [Permission]
    
    @Namespace
    private var animation
    
    @State
    var selectedPermission: Permission?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            VStack(spacing: 8) {
                Text(self.title)
                    .font(.title2)
                    .multilineTextAlignment(.leading)
                    .bold()
                    .opacity(selectedPermission != nil && permissions.count == 1 ? 0.0 : 1.0) // Hide when showing the only permission
                
                
                Text(self.description)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
                    .opacity(selectedPermission != nil ? 0.0 : 1.0)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            
            Group {
                Grid(verticalSpacing: 15) {
                    ForEach(permissions) { permission in
                        GridRow {
                            let symbolName = permission.permission.sfIconName ?? "lock"
                            
                            if selectedPermission != nil
                            {
                                Image(systemName: symbolName)
                                    .gridColumnAlignment(.center)
                            }
                            else
                            {
                                Image(systemName: symbolName)
                                    .gridColumnAlignment(.center)
                                    .matchedGeometryEffect(id: PermissionKey(key: "icon", permission: permission.permission), in: animation)
                            }

                            SwiftUI.Button(action: { show(permission) }) {
                                HStack {
                                    
                                    
                                    let text = Text(permission.localizedName)
                                        .font(.body)
                                        .bold()
                                        .minimumScaleFactor(0.1)
                                    
                                    if selectedPermission != nil
                                    {
                                        text
                                    }
                                    else
                                    {
                                        text.matchedGeometryEffect(id: PermissionKey(key: "name", permission: permission.permission), in: animation)
                                    }

                                    Spacer()

                                    Image(systemName: "info.circle")
                                        .font(.title3)
                                }
                                .contentShape(Rectangle())

                            }
                            //                        .background(Color.red)
                        }
                        .frame(minHeight: 30)
                    }
                }
                .buttonStyle(.plain) // Disable cell selection.
            }
            .opacity(selectedPermission != nil ? 0.0 : 1.0)
            
            Text(selectedPermission != nil ? "Tap to go back." : "Tap a permission to learn more.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(selectedPermission != nil && permissions.count == 1 ? 0.0 : 1.0) // Hide when showing the only permission
        }
        .frame(maxWidth: .infinity)
        .overlay(overlay, alignment: .center)
        .foregroundColor(self.tintColor)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(self.tintColor.opacity(0.3))
        , alignment: .center)
    }
    
    @ViewBuilder
    var overlay: some View {
        if let permission = selectedPermission
        {
            VStack(spacing: 15) {
                let symbolName = permission.permission.sfIconName ?? "lock"
                Image(systemName: symbolName)
                    .font(.largeTitle)
                    .matchedGeometryEffect(id: PermissionKey(key: "icon", permission: permission.permission), in: animation)
                
                Text(permission.localizedName)
                    .font(.title2)
                    .bold()
                    .minimumScaleFactor(0.1)
                    .matchedGeometryEffect(id: PermissionKey(key: "name", permission: permission.permission), in: animation)
                
                
                Text(permission.usageDescription ?? "")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
//            .background(Color.yellow)
            .onTapGesture {
                withAnimation {
                    self.selectedPermission = nil
                }
            }
        }
        else
        {
            EmptyView()
        }
    }
    
    func show(_ permission: Permission)
    {
        withAnimation {
            self.selectedPermission = permission
        }
    }
    
//    init(title: Text, description: Text, tintColor: UIColor? = nil, permissions: [Permission], selectedPermission: Permission? = nil)
//    {
//        self.title = title
//        self.description = description
//        self.tintColor = Color(uiColor: tintColor ?? UIColor.altPrimary)
//        self.permissions = permissions
//        self.selectedPermission = selectedPermission
//    }
}

@available(iOS 16, *)
struct AppPermissionsCard_Previews: PreviewProvider {
    static var previews: some View {
        
        let permissions: [ALTAppPrivacyPermission] = [
            .camera,
            .faceID,
            .appleMusic,
            .bluetooth,
            .calendars,
            .photos
        ].sorted(by: { ($0.localizedName ?? $0.rawValue) < ($1.localizedName ?? $1.rawValue) })
        
        let appPermissions = [AppPermission_Preview(localizedName: "Camera", permission: ALTAppPrivacyPermission.camera)]
//                              AppPermission_Preview(localizedName: "Face ID", permission: ALTAppPrivacyPermission.faceID),
//                              AppPermission_Preview(localizedName: "Apple Music", permission: ALTAppPrivacyPermission.appleMusic),
//                              AppPermission_Preview(localizedName: "Bluetooth", permission: ALTAppPrivacyPermission.bluetooth),
//                              AppPermission_Preview(localizedName: "Calendars", permission: ALTAppPrivacyPermission.calendars),
//                              AppPermission_Preview(localizedName: "Photos", permission: ALTAppPrivacyPermission.photos)]
        
        AppPermissionsCard(title: "Privacy",
                           description: "Delta may request access to the following:",
                           tintColor: Color(uiColor: .altPrimary),
                           permissions: appPermissions)
            .frame(width: 350)
            .previewLayout(.sizeThatFits)
    }
}
