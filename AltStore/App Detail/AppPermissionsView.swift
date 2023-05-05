//
//  AppPermissionsView.swift
//  AltStore
//
//  Created by Riley Testut on 5/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore
import AltSign

let privacyPermissions: [ALTAppPrivacyPermission] = [
    .camera,
    .faceID,
    .appleMusic,
    .bluetooth,
    .calendars,
    .photos
].sorted(by: { ($0.localizedName ?? $0.rawValue) < ($1.localizedName ?? $1.rawValue) })

let backgroundPermissions: [ALTAppBackgroundMode] = [
    .audio,
    .location,
    .fetch,
].sorted(by: { ($0.localizedName ?? $0.rawValue) < ($1.localizedName ?? $1.rawValue) })

let entitlementPermissions: [ALTEntitlement] = [
    .appGroups,
    .interAppAudio,
    .getTaskAllow,
    .keychainAccessGroups,
    .applicationIdentifier,
    .teamIdentifier,
    .init("com.apple.private.fulldiskaccess")
].sorted(by: { ($0.localizedName ?? $0.rawValue).localizedCompare(($1.localizedName ?? $1.rawValue)) == .orderedAscending })

@available(iOS 16, *)
struct AppPermissionsView: View {
    var body: some View {
        List {
            VStack(alignment: .leading) {
                Text("Description")
                    .font(.largeTitle)
                    .bold()

                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse sed ligula id dolor condimentum hendrerit. Ut vestibulum consequat massa a mattis. Praesent iaculis odio sem, nec congue orci blandit malesuada. Nunc laoreet massa sed egestas malesuada. Integer ac varius quam, at iaculis nisi. Sed id mauris id sem scelerisque tristique. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse sed ligula id dolor condimentum hendrerit. Ut vestibulum consequat massa a mattis. Praesent iaculis odio sem, nec congue orci blandit malesuada. Nunc laoreet massa sed egestas malesuada. Integer ac varius quam, at iaculis nisi. Sed id mauris id sem scelerisque tristique. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse sed ligula id dolor condimentum hendrerit. Ut vestibulum consequat massa a mattis. Praesent iaculis odio sem, nec congue orci blandit malesuada. Nunc laoreet massa sed egestas malesuada. Integer ac varius quam, at iaculis nisi. Sed id mauris id sem scelerisque tristique.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)

            VStack(alignment: .leading) {
                Text("What's New")
                    .font(.largeTitle)
                    .bold()

                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse sed ligula id dolor condimentum hendrerit. Ut vestibulum consequat massa a mattis. Praesent iaculis odio sem, nec congue orci blandit malesuada. Nunc laoreet massa sed egestas malesuada. Integer ac varius quam, at iaculis nisi. Sed id mauris id sem scelerisque tristique.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)
            
            VStack(alignment: .leading) {
                Text("Permissions")
                    .font(.largeTitle)
                    .bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)
            
//            ScrollView(.horizontal) {
//                HStack(alignment: .center, spacing: 12) {
//
//                    VStack(alignment: .center) {
//                        AppPermissionsCard(title: Text("Privacy"),
//                                           description: Text("Delta may request access to the following:"),
//                                           permissions: privacyPermissions)
//                        .frame(width: 325)
//                    }
//                    .frame(width: 350 - 18)
//
//
//                    AppPermissionsCard(title: Text("Background Modes"),
//                                       description: Text("Delta supports the following background modes:"),
//                                       permissions: backgroundPermissions)
//                }
//            }
//            .listRowSeparator(.hidden)
            
            TabView {
                AppPermissionsCard(title: Text("Privacy"),
                                   description: Text("Delta may request access to the following:"),
                                   permissions: privacyPermissions)
                .frame(width: 340)
                
                AppPermissionsCard(title: Text("Background Modes"),
                                   description: Text("Delta supports the following background modes:"),
                                   permissions: backgroundPermissions)
                .frame(width: 340)
            }
            .frame(height: 490)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .listRowSeparator(.hidden)
            
            
            Section("Entitlements") {
                ForEach(entitlementPermissions, id: \.self) { permission in
                    HStack(spacing: 15) {
                        let symbolName = permission.sfIconName ?? "lock"
                        Image(systemName: symbolName)
                            .imageScale(.large)
                            .foregroundColor(Color.purple)
                            .frame(width: 30, height: 30, alignment: .center)
                        
//                        Circle()
//                            .fill(Color.purple.opacity(0.3))
//                            .frame(width: 35)
//                            .overlay(alignment: .center) {
//                                let symbolName = permission.sfIconName ?? "lock"
//                                Image(systemName: symbolName)
//                                    .foregroundColor(Color.purple)
//                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            
                            if let localizedName = permission.localizedName
                            {
                                Text(localizedName)
                                    .font(.subheadline)

                                Text(permission.rawValue)
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                            else
                            {
                                Text(permission.rawValue)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            
            //                VStack(alignment: .leading, spacing: 20) {
            //                    Text("Entitlements")
            //                        .font(.title2)
            //
            //                    Grid(verticalSpacing: 15) {
            //                        ForEach(entitlementPermissions, id: \.self) { permission in
            //                            GridRow {
            //                                let symbolName = permission.sfIconName ?? "lock"
            //                                Image(systemName: symbolName)
            //                                    .gridColumnAlignment(.center)
            //
            //                                Text(permission.localizedName ?? permission.rawValue)
            //                                    .gridColumnAlignment(.leading)
            //                            }
            //                        }
            //                    }
            //                    .frame(maxWidth: .infinity, alignment: .leading)
            //                }
        }
        .listStyle(.plain)
        .onAppear {
            UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemPurple.withAlphaComponent(0.3)
            UIPageControl.appearance().currentPageIndicatorTintColor = UIColor.systemPurple
        }
    }
}

@available(iOS 16, *)
struct AppPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AppPermissionsView()
                .navigationTitle("Delta")
    //            .frame(width: 350)
        }
    }
}
