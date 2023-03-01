// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

extension ImageProcessors {
    /// Rounds the corners of an image to the specified radius.
    ///
    /// - warning: In order for the corners to be displayed correctly, the image must exactly match the size
    /// of the image view in which it will be displayed. See `ImageProcessor.Resize` for more info.
    public struct RoundedCorners: ImageProcessing, Hashable, CustomStringConvertible {
        private let radius: CGFloat
        private let border: ImageProcessingOptions.Border?

        /// Initializes the processor with the given radius.
        ///
        /// - parameter radius: The radius of the corners.
        /// - parameter unit: Unit of the radius, `.points` by default.
        /// - parameter border: An optional border drawn around the image.
        public init(radius: CGFloat, unit: ImageProcessingOptions.Unit = .points, border: ImageProcessingOptions.Border? = nil) {
            self.radius = radius.converted(to: unit)
            self.border = border
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            image.processed.byAddingRoundedCorners(radius: radius, border: border)
        }

        public var identifier: String {
            let suffix = border.map { ",border=\($0)" }
            return "com.github.kean/nuke/rounded_corners?radius=\(radius)" + (suffix ?? "")
        }

        public var hashableIdentifier: AnyHashable { self }

        public var description: String {
            "RoundedCorners(radius: \(radius) pixels, border: \(border?.description ?? "nil"))"
        }
    }
}
