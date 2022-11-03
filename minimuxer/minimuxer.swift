//
//  minimuxer.swift
//  minimuxer
//
//  Created by Jackson Coxson on 10/27/22.
//

import Foundation

public enum Uhoh: Error {
    case Good
    case Bad(code: Int32)
}

public func start_minimuxer(pairing_file: String) {
    let pf = NSString(string: pairing_file)
    let pf_pointer = UnsafeMutablePointer<CChar>(mutating: pf.utf8String)
    let u = NSString(string: getDocumentsDirectory().absoluteString)
    let u_ptr = UnsafeMutablePointer<CChar>(mutating: u.utf8String)
    minimuxer_c_start(pf_pointer, u_ptr)
}

public func set_usbmuxd_socket() {
    target_minimuxer_address()
}

public func debug_app(app_id: String) throws -> Uhoh {
    let ai = NSString(string: app_id)
    let ai_pointer = UnsafeMutablePointer<CChar>(mutating: ai.utf8String)
    let res = minimuxer_debug_app(ai_pointer)
    if res != 0 {
        throw Uhoh.Bad(code: res)
    }
    return Uhoh.Good
}

public func install_provisioning_profile(plist: Data) throws -> Uhoh {
    let pls = String(decoding: plist, as: UTF8.self)
    print(pls)
    print(plist)
    let x = plist.withUnsafeBytes { buf in UnsafeMutableRawPointer(mutating: buf) }
    let res = minimuxer_install_provisioning_profile(x, UInt32(plist.count))
    if res != 0 {
        throw Uhoh.Bad(code: res)
    }
    return Uhoh.Good
}

public func remove_provisioning_profile(id: String) throws -> Uhoh {
    let id_ns = NSString(string: id)
    let id_pointer = UnsafeMutablePointer<CChar>(mutating: id_ns.utf8String)
    let res = minimuxer_remove_provisioning_profile(id_pointer)
    if res != 0 {
        throw Uhoh.Bad(code: res)
    }
    return Uhoh.Good
}

public func remove_app(app_id: String) throws -> Uhoh {
    let ai = NSString(string: app_id)
    let ai_pointer = UnsafeMutablePointer<CChar>(mutating: ai.utf8String)
    let res = minimuxer_remove_app(ai_pointer)
    if res != 0 {
        throw Uhoh.Bad(code: res)
    }
    return Uhoh.Good
}

public func auto_mount_dev_image() {
    let u = NSString(string: getDocumentsDirectory().absoluteString)
    let u_ptr = UnsafeMutablePointer<CChar>(mutating: u.utf8String)
    minimuxer_auto_mount(u_ptr)
}

func getDocumentsDirectory() -> URL {
    // find all possible documents directories for this user
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    // just send back the first one, which ought to be the only one
    return paths[0]
}
