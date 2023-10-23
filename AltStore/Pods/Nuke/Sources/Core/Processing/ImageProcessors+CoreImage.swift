// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(tvOS) || os(macOS)

import Foundation
import CoreImage

extension ImageProcessors {

    /// Applies Core Image filter (`CIFilter`) to the image.
    ///
    /// # Performance Considerations.
    ///
    /// Prefer chaining multiple `CIFilter` objects using `Core Image` facilities
    /// instead of using multiple instances of `ImageProcessors.CoreImageFilter`.
    ///
    /// # References
    ///
    /// - [Core Image Programming Guide](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html)
    /// - [Core Image Filter Reference](https://developer.apple.com/library/prerelease/ios/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
    public struct CoreImageFilter: ImageProcessing, CustomStringConvertible {
        private let name: String
        private let parameters: [String: Any]
        public let identifier: String

        /// - parameter identifier: Uniquely identifies the processor.
        public init(name: String, parameters: [String: Any], identifier: String) {
            self.name = name
            self.parameters = parameters
            self.identifier = identifier
        }

        public init(name: String) {
            self.name = name
            self.parameters = [:]
            self.identifier = "com.github.kean/nuke/core_image?name=\(name))"
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            let filter = CIFilter(name: name, parameters: parameters)
            return CoreImageFilter.apply(filter: filter, to: image)
        }

        // MARK: - Apply Filter

        /// A default context shared between all Core Image filters. The context
        /// has `.priorityRequestLow` option set to `true`.
        public static var context = CIContext(options: [.priorityRequestLow: true])

        public static func apply(filter: CIFilter?, to image: PlatformImage) -> PlatformImage? {
            guard let filter = filter else {
                return nil
            }
            return applyFilter(to: image) {
                filter.setValue($0, forKey: kCIInputImageKey)
                return filter.outputImage
            }
        }

        static func applyFilter(to image: PlatformImage, context: CIContext = context, closure: (CoreImage.CIImage) -> CoreImage.CIImage?) -> PlatformImage? {
            let ciImage: CoreImage.CIImage? = {
                if let image = image.ciImage {
                    return image
                }
                if let image = image.cgImage {
                    return CoreImage.CIImage(cgImage: image)
                }
                return nil
            }()
            guard let inputImage = ciImage, let outputImage = closure(inputImage) else {
                return nil
            }
            guard let imageRef = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }
            return PlatformImage.make(cgImage: imageRef, source: image)
        }

        public var description: String {
            "CoreImageFilter(name: \(name), parameters: \(parameters))"
        }
    }
}

#endif
