// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

func signpost(_ log: OSLog, _ object: AnyObject, _ name: StaticString, _ type: SignpostType) {
    guard ImagePipeline.Configuration.isSignpostLoggingEnabled else { return }
    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
        let signpostId = OSSignpostID(log: log, object: object)
        os_signpost(type.os, log: log, name: name, signpostID: signpostId)
    }
}

func signpost(_ log: OSLog, _ object: AnyObject, _ name: StaticString, _ type: SignpostType, _ message: @autoclosure () -> String) {
    guard ImagePipeline.Configuration.isSignpostLoggingEnabled else { return }
    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
        let signpostId = OSSignpostID(log: log, object: object)
        os_signpost(type.os, log: log, name: name, signpostID: signpostId, "%{public}s", message())
    }
}

func signpost<T>(_ log: OSLog, _ name: StaticString, _ work: () -> T) -> T {
    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *), ImagePipeline.Configuration.isSignpostLoggingEnabled {
        let signpostId = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostId)
        let result = work()
        os_signpost(.end, log: log, name: name, signpostID: signpostId)
        return result
    } else {
        return work()
    }
}

func signpost<T>(_ log: OSLog, _ name: StaticString, _ message: @autoclosure () -> String, _ work: () -> T) -> T {
    if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *), ImagePipeline.Configuration.isSignpostLoggingEnabled {
        let signpostId = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostId, "%{public}s", message())
        let result = work()
        os_signpost(.end, log: log, name: name, signpostID: signpostId)
        return result
    } else {
        return work()
    }
}

var log: OSLog = .disabled

private let byteFormatter = ByteCountFormatter()

enum Formatter {
    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}

enum SignpostType {
    case begin, event, end

    @available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    var os: OSSignpostType {
        switch self {
        case .begin: return .begin
        case .event: return .event
        case .end: return .end
        }
    }
}
