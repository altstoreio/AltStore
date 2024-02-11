// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import CommonCrypto

extension String {
    /// Calculates SHA1 from the given string and returns its hex representation.
    ///
    /// ```swift
    /// print("http://test.com".sha1)
    /// // prints "50334ee0b51600df6397ce93ceed4728c37fee4e"
    /// ```
    var sha1: String? {
        guard !isEmpty, let input = self.data(using: .utf8) else {
            return nil
        }

        let hash = input.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.baseAddress, CC_LONG(input.count), &hash)
            return hash
        }

        return hash.map({ String(format: "%02x", $0) }).joined()
    }
}

extension NSLock {
    func sync<T>(_ closure: () -> T) -> T {
        lock()
        defer { unlock() }
        return closure()
    }
}

extension URL {
    var isCacheable: Bool {
        let scheme = self.scheme
        return scheme != "file" && scheme != "data"
    }
}

extension OperationQueue {
    convenience init(maxConcurrentCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentCount
    }
}

extension ImageRequest.Priority {
    var taskPriority: TaskPriority {
        switch self {
        case .veryLow: return .veryLow
        case .low: return .low
        case .normal: return .normal
        case .high: return .high
        case .veryHigh: return .veryHigh
        }
    }
}
