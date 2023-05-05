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
        var permission: Permission
    }
}


@available(iOS 16, *)
struct AppPermissionsCard<Permission: ALTAppPermission>: View
{
    let title: Text
    let description: Text
    
    @State
    var permissions: [Permission]
    
    @Namespace
    private var animation
    
    @State
    var selectedPermission: Permission?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            VStack(spacing: 8) {
                self.title
                    .font(.title2)
                    .bold()
                
                
                self.description
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
                    .opacity(selectedPermission != nil ? 0.0 : 1.0)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            
            Group {
                Grid(verticalSpacing: 15) {
                    ForEach(permissions, id: \.self) { permission in
                        GridRow {
                            let symbolName = permission.sfIconName ?? "lock"
                            Image(systemName: symbolName)
                                .gridColumnAlignment(.center)
                                .matchedGeometryEffect(id: PermissionKey(key: "icon", permission: permission), in: animation)
                            
                            SwiftUI.Button(action: { show(permission) }) {
                                HStack {
                                    Text(permission.localizedName ?? permission.rawValue)
                                        .font(.body)
                                        .bold()
                                        .minimumScaleFactor(0.1)
//                                        .frame(maxWidth: .infinity, alignment: .leading)
//                                        .contentShape(Rectangle()) // Extend tap area
                                        .matchedGeometryEffect(id: PermissionKey(key: "name", permission: permission), in: animation)
                                    
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
            
            let text = select
            Text(selectedPermission != nil ? "Tap to go back." : "Tap a permission to learn more.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .overlay(overlay, alignment: .center)
        .foregroundColor(Color.purple)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.purple.opacity(0.3))
        , alignment: .center)
    }
    
    @ViewBuilder
    var overlay: some View {
        if let permission = selectedPermission
        {
            VStack(spacing: 15) {
                let symbolName = permission.sfIconName ?? "lock"
                Image(systemName: symbolName)
                    .font(.largeTitle)
                    .matchedGeometryEffect(id: PermissionKey(key: "icon", permission: permission), in: animation)
                
                Text(permission.localizedName ?? permission.rawValue)
                    .font(.title2)
                    .bold()
                    .minimumScaleFactor(0.1)
                    .matchedGeometryEffect(id: PermissionKey(key: "name", permission: permission), in: animation)
                
                
                Text("Allows Delta to use images from your Photo Library as game artwork.")
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
        
        AppPermissionsCard(title: Text("Privacy"),
                           description: Text("Delta may request access to the following:"),
                           permissions: permissions)
            .frame(width: 350)
            .previewLayout(.sizeThatFits)
    }
}
