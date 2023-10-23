// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

extension ImageProcessors {
    /// Scales an image to a specified size.
    public struct Resize: ImageProcessing, Hashable, CustomStringConvertible {
        private let size: Size
        private let contentMode: ContentMode
        private let crop: Bool
        private let upscale: Bool

        /// An option for how to resize the image.
        public enum ContentMode: CustomStringConvertible {
            /// Scales the image so that it completely fills the target area.
            /// Maintains the aspect ratio of the original image.
            case aspectFill

            /// Scales the image so that it fits the target size. Maintains the
            /// aspect ratio of the original image.
            case aspectFit

            public var description: String {
                switch self {
                case .aspectFill: return ".aspectFill"
                case .aspectFit: return ".aspectFit"
                }
            }
        }

        /// Initializes the processor with the given size.
        ///
        /// - parameter size: The target size.
        /// - parameter unit: Unit of the target size, `.points` by default.
        /// - parameter contentMode: `.aspectFill` by default.
        /// - parameter crop: If `true` will crop the image to match the target size.
        /// Does nothing with content mode .aspectFill. `false` by default.
        /// - parameter upscale: `false` by default.
        public init(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) {
            self.size = Size(size: size, unit: unit)
            self.contentMode = contentMode
            self.crop = crop
            self.upscale = upscale
        }

        /// Scales an image to the given width preserving aspect ratio.
        ///
        /// - parameter width: The target width.
        /// - parameter unit: Unit of the target size, `.points` by default.
        /// - parameter upscale: `false` by default.
        public init(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: width, height: 9999), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        /// Scales an image to the given height preserving aspect ratio.
        ///
        /// - parameter height: The target height.
        /// - parameter unit: Unit of the target size, `.points` by default.
        /// - parameter upscale: `false` by default.
        public init(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) {
            self.init(size: CGSize(width: 9999, height: height), unit: unit, contentMode: .aspectFit, crop: false, upscale: upscale)
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            if crop && contentMode == .aspectFill {
                return image.processed.byResizingAndCropping(to: size.cgSize)
            }
            return image.processed.byResizing(to: size.cgSize, contentMode: contentMode, upscale: upscale)
        }

        public var identifier: String {
            "com.github.kean/nuke/resize?s=\(size.cgSize),cm=\(contentMode),crop=\(crop),upscale=\(upscale)"
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "Resize(size: \(size.cgSize) pixels, contentMode: \(contentMode), crop: \(crop), upscale: \(upscale))"
        }
    }
}

// Adds Hashable without making changes to public CGSize API
private struct Size: Hashable {
    let cgSize: CGSize
    
    /// Creates the size in pixels by scaling to the input size to the screen scale
    /// if needed.
    init(size: CGSize, unit: ImageProcessingOptions.Unit) {
        switch unit {
        case .pixels: self.cgSize = size // The size is already in pixels
        case .points: self.cgSize = size.scaled(by: Screen.scale)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cgSize.width)
        hasher.combine(cgSize.height)
    }
}
