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

/// A namespace for all processors that implement `ImageProcessing` protocol.
public enum ImageProcessors {}

#if swift(>=5.5)
extension ImageProcessing where Self == ImageProcessors.Resize {
    /// Scales an image to a specified size.
    ///
    /// - parameter size: The target size.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter contentMode: `.aspectFill` by default.
    /// - parameter crop: If `true` will crop the image to match the target size.
    /// Does nothing with content mode .aspectFill. `false` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(size: CGSize, unit: ImageProcessingOptions.Unit = .points, contentMode: ImageProcessors.Resize.ContentMode = .aspectFill, crop: Bool = false, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(size: size, unit: unit, contentMode: contentMode, crop: crop, upscale: upscale)
    }
    
    /// Scales an image to the given width preserving aspect ratio.
    ///
    /// - parameter width: The target width.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(width: width, unit: unit, upscale: upscale)
    }

    /// Scales an image to the given height preserving aspect ratio.
    ///
    /// - parameter height: The target height.
    /// - parameter unit: Unit of the target size, `.points` by default.
    /// - parameter upscale: `false` by default.
    public static func resize(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, upscale: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(height: height, unit: unit, upscale: upscale)
    }
}

extension ImageProcessing where Self == ImageProcessors.Circle {
    /// Rounds the corners of an image into a circle. If the image is not a square,
    /// crops it to a square first.
    ///
    /// - parameter border: `nil` by default.
    public static func circle(border: ImageProcessingOptions.Border? = nil) -> ImageProcessors.Circle {
        ImageProcessors.Circle(border: border)
    }
}

extension ImageProcessing where Self == ImageProcessors.RoundedCorners {
    /// Rounds the corners of an image to the specified radius.
    ///
    /// - parameter radius: The radius of the corners.
    /// - parameter unit: Unit of the radius, `.points` by default.
    /// - parameter border: An optional border drawn around the image.
    ///
    /// - warning: In order for the corners to be displayed correctly, the image must exactly match the size
    /// of the image view in which it will be displayed. See `ImageProcessor.Resize` for more info.
    public static func roundedCorners(radius: CGFloat, unit: ImageProcessingOptions.Unit = .points, border: ImageProcessingOptions.Border? = nil) -> ImageProcessors.RoundedCorners {
        ImageProcessors.RoundedCorners(radius: radius, unit: unit, border: border)
    }
}

#if os(iOS) || os(tvOS) || os(macOS)

extension ImageProcessing where Self == ImageProcessors.CoreImageFilter {
    /// Applies Core Image filter (`CIFilter`) to the image.
    ///
    /// - parameter identifier: Uniquely identifies the processor.
    public static func coreImageFilter(name: String, parameters: [String: Any], identifier: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name, parameters: parameters, identifier: identifier)
    }
    
    /// Applies Core Image filter (`CIFilter`) to the image.
    ///
    public static func coreImageFilter(name: String) -> ImageProcessors.CoreImageFilter {
        ImageProcessors.CoreImageFilter(name: name)
    }
}

extension ImageProcessing where Self == ImageProcessors.GaussianBlur {
    /// Blurs an image using `CIGaussianBlur` filter.
    ///
    /// - parameter radius: `8` by default.
    public static func gaussianBlur(radius: Int = 8) -> ImageProcessors.GaussianBlur {
        ImageProcessors.GaussianBlur(radius: radius)
    }
}

#endif

extension ImageProcessing where Self == ImageProcessors.Anonymous {
    /// Processed an image using a specified closure.
    public static func process(id: String, _ closure: @escaping (PlatformImage) -> PlatformImage?) -> ImageProcessors.Anonymous {
        ImageProcessors.Anonymous(id: id, closure)
    }
}
#endif
