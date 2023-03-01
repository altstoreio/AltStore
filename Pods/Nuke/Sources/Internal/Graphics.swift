// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(watchOS)
import ImageIO
import CoreGraphics
import WatchKit
#endif

#if os(macOS)
import Cocoa
#endif

extension PlatformImage {
    var processed: ImageProcessingExtensions {
        ImageProcessingExtensions(image: self)
    }
}

struct ImageProcessingExtensions {
    let image: PlatformImage

    func byResizing(to targetSize: CGSize,
                    contentMode: ImageProcessors.Resize.ContentMode,
                    upscale: Bool) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let targetSize = targetSize.rotatedForOrientation(image.imageOrientation)
        #endif
        let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: contentMode)
        guard scale < 1 || upscale else {
            return image // The image doesn't require scaling
        }
        let size = cgImage.size.scaled(by: scale).rounded()
        return image.draw(inCanvasWithSize: size)
    }

    /// Crops the input image to the given size and resizes it if needed.
    /// - note: this method will always upscale.
    func byResizingAndCropping(to targetSize: CGSize) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let targetSize = targetSize.rotatedForOrientation(image.imageOrientation)
        #endif
        let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: .aspectFill)
        let scaledSize = cgImage.size.scaled(by: scale)
        let drawRect = scaledSize.centeredInRectWithSize(targetSize)
        return image.draw(inCanvasWithSize: targetSize, drawRect: drawRect)
    }

    func byDrawingInCircle(border: ImageProcessingOptions.Border?) -> PlatformImage? {
        guard let squared = byCroppingToSquare(), let cgImage = squared.cgImage else {
            return nil
        }
        let radius = CGFloat(cgImage.width) // Can use any dimension since image is a square
        return squared.processed.byAddingRoundedCorners(radius: radius / 2.0, border: border)
    }

    /// Draws an image in square by preserving an aspect ratio and filling the
    /// square if needed. If the image is already a square, returns an original image.
    func byCroppingToSquare() -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        guard cgImage.width != cgImage.height else {
            return image // Already a square
        }

        let imageSize = cgImage.size
        let side = min(cgImage.width, cgImage.height)
        let targetSize = CGSize(width: side, height: side)
        let cropRect = CGRect(origin: .zero, size: targetSize).offsetBy(
            dx: max(0, (imageSize.width - targetSize.width) / 2),
            dy: max(0, (imageSize.height - targetSize.height) / 2)
        )
        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }
        return PlatformImage.make(cgImage: cropped, source: image)
    }

    /// Adds rounded corners with the given radius to the image.
    /// - parameter radius: Radius in pixels.
    /// - parameter border: Optional stroke border.
    func byAddingRoundedCorners(radius: CGFloat, border: ImageProcessingOptions.Border? = nil) -> PlatformImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        guard let ctx = CGContext.make(cgImage, size: cgImage.size, alphaInfo: .premultipliedLast) else {
            return nil
        }
        let rect = CGRect(origin: CGPoint.zero, size: cgImage.size)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(cgImage, in: CGRect(origin: CGPoint.zero, size: cgImage.size))

        if let border = border {
            ctx.setStrokeColor(border.color.cgColor)
            ctx.addPath(path)
            ctx.setLineWidth(border.width)
            ctx.strokePath()
        }
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return PlatformImage.make(cgImage: outputCGImage, source: image)
    }
}

extension PlatformImage {
    /// Draws the image in a `CGContext` in a canvas with the given size using
    /// the specified draw rect.
    ///
    /// For example, if the canvas size is `CGSize(width: 10, height: 10)` and
    /// the draw rect is `CGRect(x: -5, y: 0, width: 20, height: 10)` it would
    /// draw the input image (which is horizontal based on the known draw rect)
    /// in a square by centering it in the canvas.
    ///
    /// - parameter drawRect: `nil` by default. If `nil` will use the canvas rect.
    func draw(inCanvasWithSize canvasSize: CGSize, drawRect: CGRect? = nil) -> PlatformImage? {
        guard let cgImage = cgImage else {
            return nil
        }
        guard let ctx = CGContext.make(cgImage, size: canvasSize) else {
            return nil
        }
        ctx.draw(cgImage, in: drawRect ?? CGRect(origin: .zero, size: canvasSize))
        guard let outputCGImage = ctx.makeImage() else {
            return nil
        }
        return PlatformImage.make(cgImage: outputCGImage, source: self)
    }

    /// Decompresses the input image by drawing in the the `CGContext`.
    func decompressed() -> PlatformImage? {
        guard let cgImage = cgImage else {
            return nil
        }
        return draw(inCanvasWithSize: cgImage.size, drawRect: CGRect(origin: .zero, size: cgImage.size))
    }
}

private extension CGContext {
    static func make(_ image: CGImage, size: CGSize, alphaInfo: CGImageAlphaInfo? = nil) -> CGContext? {
        let alphaInfo: CGImageAlphaInfo = alphaInfo ?? (image.isOpaque ? .noneSkipLast : .premultipliedLast)

        // Create the context which matches the input image.
        if let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) {
            return ctx
        }

        // In case the combination of parameters (color space, bits per component, etc)
        // is nit supported by Core Graphics, switch to default context.
        // - Quartz 2D Programming Guide
        // - https://github.com/kean/Nuke/issues/35
        // - https://github.com/kean/Nuke/issues/57
        return CGContext(
            data: nil,
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )
    }
}

extension CGFloat {
    func converted(to unit: ImageProcessingOptions.Unit) -> CGFloat {
        switch unit {
        case .pixels: return self
        case .points: return self * Screen.scale
        }
    }
}

extension CGSize {
    func getScale(targetSize: CGSize, contentMode: ImageProcessors.Resize.ContentMode) -> CGFloat {
        let scaleHor = targetSize.width / width
        let scaleVert = targetSize.height / height

        switch contentMode {
        case .aspectFill:
            return max(scaleHor, scaleVert)
        case .aspectFit:
            return min(scaleHor, scaleVert)
        }
    }

    /// Calculates a rect such that the output rect will be in the center of
    /// the rect of the input size (assuming origin: .zero)
    func centeredInRectWithSize(_ targetSize: CGSize) -> CGRect {
        // First, resize the original size to fill the target size.
        CGRect(origin: .zero, size: self).offsetBy(
            dx: -(width - targetSize.width) / 2,
            dy: -(height - targetSize.height) / 2
        )
    }
}

#if os(iOS) || os(tvOS) || os(watchOS)
private extension CGSize {
    func rotatedForOrientation(_ imageOrientation: UIImage.Orientation) -> CGSize {
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width) // Rotate 90 degrees
        case .up, .upMirrored, .down, .downMirrored:
            return self
        @unknown default:
            return self
        }
    }
}
#endif

#if os(macOS)
extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var ciImage: CIImage? {
        cgImage.map { CIImage(cgImage: $0) }
    }

    static func make(cgImage: CGImage, source: NSImage) -> NSImage {
        NSImage(cgImage: cgImage, size: .zero)
    }
    
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}
#else
extension UIImage {
    static func make(cgImage: CGImage, source: UIImage) -> UIImage {
        UIImage(cgImage: cgImage, scale: source.scale, orientation: source.imageOrientation)
    }
}
#endif

extension CGImage {
    /// Returns `true` if the image doesn't contain alpha channel.
    var isOpaque: Bool {
        let alpha = alphaInfo
        return alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    func rounded() -> CGSize {
        CGSize(width: CGFloat(round(width)), height: CGFloat(round(height)))
    }
}

struct Screen {
    #if os(iOS) || os(tvOS)
    /// Returns the current screen scale.
    static var scale: CGFloat { UIScreen.main.scale }
    #elseif os(watchOS)
    /// Returns the current screen scale.
    static var scale: CGFloat { WKInterfaceDevice.current().screenScale }
    #elseif os(macOS)
    /// Always returns 1.
    static var scale: CGFloat { 1 }
    #endif
}

#if os(macOS)
typealias Color = NSColor
#else
typealias Color = UIColor
#endif

extension Color {
    /// Returns a hex representation of the color, e.g. "#FFFFAA".
    var hex: String {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let components = [r, g, b, a < 1 ? a : nil]
        return "#" + components
            .compactMap { $0 }
            .map { String(format: "%02lX", lroundf(Float($0) * 255)) }
            .joined()
    }
}

/// Creates an image thumbnail. Uses significantly less memory than other options.
func makeThumbnail(data: Data, options: ImageRequest.ThumbnailOptions) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
        return nil
    }
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: options.createThumbnailFromImageAlways,
        kCGImageSourceCreateThumbnailFromImageIfAbsent: options.createThumbnailFromImageIfAbsent,
        kCGImageSourceShouldCacheImmediately: options.shouldCacheImmediately,
        kCGImageSourceCreateThumbnailWithTransform: options.createThumbnailWithTransform,
        kCGImageSourceThumbnailMaxPixelSize: options.maxPixelSize] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return PlatformImage(cgImage: image)
}
