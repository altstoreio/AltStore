//
//  AppPermissionType.swift
//  AltStoreCore
//
//  Created by Riley Testut on 5/3/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AltSign

public extension ALTAppPermissionType
{
    var localizedName: String? {
        switch self
        {
        case .entitlement: return NSLocalizedString("Entitlement", comment: "")
        case .backgroundMode: return NSLocalizedString("Background Mode", comment: "")
        case .privacy: return NSLocalizedString("Privacy Permission", comment: "")
        @unknown default: return nil
        }
    }
}


public protocol ALTAppPermission: RawRepresentable<String>, Hashable
{
    var type: ALTAppPermissionType { get }
    var localizedName: String? { get }
    var localizedShortName: String? { get }
    var icon: UIImage? { get }
    
    var localizedExplanation: String? { get }
    
    var sfIconName: String? { get }
    
    func isEqual(to permission: any ALTAppPermission) -> Bool
}

extension ALTAppPermission
{
    public var sfIconName: String? { nil }
    public var localizedExplanation: String? { nil }
    
    public var localizedDisplayName: String {
        return self.localizedName ?? self.rawValue
    }
    
    public func isEqual(to permission: any ALTAppPermission) -> Bool
    {
        guard let permission = permission as? Self else { return false }
        return self == permission
    }
}

//extension Array where Element == any ALTAppPermission
//{
//    public static func ==(lhs: [any ALTAppPermission], rhs: [any ALTAppPermission]) -> Bool
//    {
//        guard lhs.count == rhs.count else { return false }
//        
//        let isEqual = zip(lhs, rhs).allSatisfy { $0.isEqual(to: $1) }
//        return isEqual
//    }
//}

//public func ==(lhs: [any ALTAppPermission], rhs: [any ALTAppPermission]) -> Bool
//{
//    guard lhs.count == rhs.count else { return false }
//    
//    let isEqual = zip(lhs, rhs).allSatisfy { $0.isEqual(to: $1) }
//    return isEqual
//}

extension ALTAppBackgroundMode: ALTAppPermission
{
    public var type: ALTAppPermissionType {
        return .backgroundMode
    }
    
    public var localizedName: String? {
        switch self
        {
        case .audio: return NSLocalizedString("Play Audio", comment: "")
        case .location: return NSLocalizedString("Track Your Location", comment: "")
        case .fetch: return NSLocalizedString("Fetch Data", comment: "")
        case .processing: return NSLocalizedString("Process Data", comment: "")
        case .voIP: return NSLocalizedString("Receive VoIP Calls", comment: "")
//        case .remoteNotification: NSLocalizedString("Receive Push Notifications", comment: "")
        default: return nil
        }
    }
    
    public var localizedShortName: String? {
        switch self
        {
        case .audio: return NSLocalizedString("Audio (BG)", comment: "")
        case .location: return NSLocalizedString("Location (BG)", comment: "")
        case .fetch: return NSLocalizedString("Fetch (BG)", comment: "")
        default: return nil
        }
    }
    
    public var icon: UIImage? {
        switch self
        {
        case .audio: return UIImage(named: "BackgroundAudioPermission")
        case .location: return UIImage(systemName: "location")
        case .fetch: return UIImage(named: "BackgroundFetchPermission")
        default: return nil
        }
    }
    
    public var sfIconName: String? {
        switch self
        {
        case .audio: return "speaker.wave.3"
        case .location: return "location"
        case .fetch: return "arrow.down.to.line"
        default: return nil
        }
    }
}

extension ALTAppPrivacyPermission: ALTAppPermission
{
    public var type: ALTAppPermissionType {
        return .privacy
    }
    
    public var localizedName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .camera: return NSLocalizedString("Camera", comment: "")
        case .faceID: return NSLocalizedString("Face ID", comment: "")
        case .appleMusic: return NSLocalizedString("Apple Music", comment: "")
        case .localNetwork: return NSLocalizedString("Local Network", comment: "")
//        case .bluetooth: return UIImage(systemName: "camera")
        case .calendars: return NSLocalizedString("Calendars", comment: "")
        default: return nil
        }
    }
    
    public var localizedShortName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        default: return nil
        }
    }
    
    public var icon: UIImage? {
        switch self
        {
        case .photos: return UIImage(named: "PhotosPermission")
        case .camera: return UIImage(systemName: "camera")
        case .faceID: return UIImage(systemName: "faceid")
        case .appleMusic: return UIImage(systemName: "music.note")
//        case .bluetooth: return UIImage(systemName: "camera")
        case .calendars: return UIImage(systemName: "calendar")
        default: return nil
        }
    }
    
    
    public var sfIconName: String? {
        switch self
        {
        case .photos: return "photo"
        case .camera: return "camera"
        case .faceID: return "faceid"
        case .appleMusic: return "music.note"
        case .localNetwork: return "wifi"
//        case .bluetooth: return UIImage(systemName: "camera")
        case .calendars: return "calendar"
        default: return nil
        }
    }
}

extension ALTEntitlement: ALTAppPermission
{
    public var type: ALTAppPermissionType {
        return .entitlement
    }
    
    public var localizedName: String? {
        switch self
        {
        case .appGroups: return NSLocalizedString("App Groups", comment: "")
        case .keychainAccessGroups: return NSLocalizedString("Keychain", comment: "")
        case .interAppAudio: return NSLocalizedString("Inter-App Audio", comment: "")
        case .getTaskAllow: return NSLocalizedString("Debuggable", comment: "")
        case .gameCenter: return NSLocalizedString("Game Center", comment: "")
        default: return nil
        }
    }
    
    public var localizedShortName: String? {
        return self.localizedName
    }
    
    public var icon: UIImage? {
        switch self
        {
        case .appGroups: return UIImage(systemName: "rectangle.3.group")
        case .keychainAccessGroups: return UIImage(systemName: "key")
        case .interAppAudio: return UIImage(systemName: "speaker.square")
        case .getTaskAllow: return UIImage(systemName: "hammer")
        case .gameCenter: return UIImage(systemName: "gamecontroller")
        default: return nil
        }
    }
    
    public var sfIconName: String? {
        switch self
        {
        case .appGroups: return "rectangle.3.group"
        case .keychainAccessGroups: return "key"
        case .interAppAudio: return "speaker.square"
        case .getTaskAllow: return "hammer"
        case .gameCenter: return "gamecontroller"
        default: return nil
        }
    }
    
    public var localizedExplanation: String? {
        switch self
        {
        case .appGroups: return NSLocalizedString("Allows sharing files with other apps and app extensions with same group.", comment: "")
        case .keychainAccessGroups: return NSLocalizedString("Allows reading and writing secure data to the system's keychain.", comment: "")
        case .interAppAudio: return NSLocalizedString("Allows sharing real-time audio between apps.", comment: "")
        case .getTaskAllow: return NSLocalizedString("Allows developers to attach a debugger to this app. This permission is required for JIT to work.", comment: "")
        case .gameCenter: return NSLocalizedString("Allows the app to share your scores with a global leaderboard.", comment: "")
        default: return nil
        }
    }
}
