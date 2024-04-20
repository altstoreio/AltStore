// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(watchOS)
import WatchKit
#endif

#if os(macOS)
import Cocoa
#endif

/// A namespace with shared image processing options.
public enum ImageProcessingOptions {

    public enum Unit: CustomStringConvertible {
        case points
        case pixels

        public var description: String {
            switch self {
            case .points: return "points"
            case .pixels: return "pixels"
            }
        }
    }

    /// Draws a border.
    ///
    /// - warning: To make sure that the border looks the way you expect,
    /// make sure that the images you display exactly match the size of the
    /// views in which they get displayed. If you can't guarantee that, pleasee
    /// consider adding border to a view layer. This should be your primary
    /// option regardless.
    public struct Border: Hashable, CustomStringConvertible {
        public let width: CGFloat

        #if os(iOS) || os(tvOS) || os(watchOS)
        public let color: UIColor

        /// - parameter color: Border color.
        /// - parameter width: Border width. 1 points by default.
        /// - parameter unit: Unit of the width, `.points` by default.
        public init(color: UIColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }
        #else
        public let color: NSColor

        /// - parameter color: Border color.
        /// - parameter width: Border width. 1 points by default.
        /// - parameter unit: Unit of the width, `.points` by default.
        public init(color: NSColor, width: CGFloat = 1, unit: Unit = .points) {
            self.color = color
            self.width = width.converted(to: unit)
        }
        #endif

        public var description: String {
            "Border(color: \(color.hex), width: \(width) pixels)"
        }
    }
}
