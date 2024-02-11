// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

#if os(watchOS)
import WatchKit
#endif

/// A namespace with all available decoders.
public enum ImageDecoders {}

extension ImageDecoders {

    /// A decoder that supports all of the formats natively supported by the system.
    ///
    /// - note: The decoder automatically sets the scale of the decoded images to
    /// match the scale of the screen.
    ///
    /// - note: The default decoder supports progressive JPEG. It produces a new
    /// preview every time it encounters a new full frame.
    public final class Default: ImageDecoding, ImageDecoderRegistering {
        // Number of scans that the decoder has found so far. The last scan might be
        // incomplete at this point.
        var numberOfScans: Int { scanner.numberOfScans }
        private var scanner = ProgressiveJPEGScanner()

        private var container: ImageContainer?

        private var isDecodingGIFProgressively = false
        private var isPreviewForGIFGenerated = false
        private var scale: CGFloat?
        private var thumbnail: ImageRequest.ThumbnailOptions?

        public init() { }

        public var isAsynchronous: Bool {
            thumbnail != nil
        }

        public init?(data: Data, context: ImageDecodingContext) {
            self.scale = context.request.scale
            self.thumbnail = context.request.thubmnail
            guard let container = _decode(data) else {
                return nil
            }
            self.container = container
        }

        public init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
            let imageType = AssetType(data)

            self.scale = context.request.scale
            self.thumbnail = context.request.thubmnail

            // Determined whether the image supports progressive decoding or not
            // (only proressive JPEG is allowed for now, but you can add support
            // for other formats by implementing your own decoder).
            if imageType == .jpeg, ImageProperties.JPEG(data)?.isProgressive == true {
                return
            }

            // Generate one preview for GIF.
            if imageType == .gif {
                self.isDecodingGIFProgressively = true
                return
            }

            return nil
        }

        public func decode(_ data: Data) -> ImageContainer? {
            container ?? _decode(data)
        }

        private func _decode(_ data: Data) -> ImageContainer? {
            func makeImage() -> PlatformImage? {
                if let thumbnail = self.thumbnail {
                    return makeThumbnail(data: data, options: thumbnail)
                }
                return ImageDecoders.Default._decode(data, scale: scale)
            }
            guard let image = autoreleasepool(invoking: makeImage) else {
                return nil
            }
            // Keep original data around in case of GIF
            let type = AssetType(data)
            if ImagePipeline.Configuration._isAnimatedImageDataEnabled, type == .gif {
                image._animatedImageData = data
            }
            var container = ImageContainer(image: image, data: image._animatedImageData)
            container.type = type
            if type == .gif {
                container.data = data
            }
            if numberOfScans > 0 {
                container.userInfo[.scanNumberKey] = numberOfScans
            }
            if thumbnail != nil {
                container.userInfo[.isThumbnailKey] = true
            }
            return container
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            if isDecodingGIFProgressively { // Special handling for GIF
                if !isPreviewForGIFGenerated, let image = ImageDecoders.Default._decode(data, scale: scale) {
                    isPreviewForGIFGenerated = true
                    return ImageContainer(image: image, type: .gif, isPreview: true, data: nil, userInfo: [:])
                }
                return nil
            }

            guard let endOfScan = scanner.scan(data), endOfScan > 0 else {
                return nil
            }
            guard let image = ImageDecoders.Default._decode(data[0...endOfScan], scale: scale) else {
                return nil
            }
            return ImageContainer(image: image, type: .jpeg, isPreview: true, userInfo: [.scanNumberKey: numberOfScans])
        }
    }
}

private struct ProgressiveJPEGScanner {
    // Number of scans that the decoder has found so far. The last scan might be
    // incomplete at this point.
    private(set) var numberOfScans = 0
    private var lastStartOfScan: Int = 0 // Index of the last found Start of Scan
    private var scannedIndex: Int = -1 // Index at which previous scan was finished

    /// Scans the given data. If finds new scans, returns the last index of the
    /// last available scan.
    mutating func scan(_ data: Data) -> Int? {
        // Check if there is more data to scan.
        guard (scannedIndex + 1) < data.count else {
            return nil
        }

        // Start scaning from the where it left off previous time.
        var index = (scannedIndex + 1)
        var numberOfScans = self.numberOfScans
        while index < (data.count - 1) {
            scannedIndex = index
            // 0xFF, 0xDA - Start Of Scan
            if data[index] == 0xFF, data[index + 1] == 0xDA {
                lastStartOfScan = index
                numberOfScans += 1
            }
            index += 1
        }

        // Found more scans this the previous time
        guard numberOfScans > self.numberOfScans else {
            return nil
        }
        self.numberOfScans = numberOfScans

        // `> 1` checks that we've received a first scan (SOS) and then received
        // and also received a second scan (SOS). This way we know that we have
        // at least one full scan available.
        guard numberOfScans > 1 && lastStartOfScan > 0 else {
            return nil
        }

        return lastStartOfScan - 1
    }
}

extension ImageDecoders.Default {
    private static func _decode(_ data: Data, scale: CGFloat?) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data, scale: scale ?? Screen.scale)
        #endif
    }
}

enum ImageProperties {}

// Keeping this private for now, not sure neither about the API, not the implementation.
extension ImageProperties {
    struct JPEG {
        public var isProgressive: Bool

        public init?(_ data: Data) {
            guard let isProgressive = ImageProperties.JPEG.isProgressive(data) else {
                return nil
            }
            self.isProgressive = isProgressive
        }

        private static func isProgressive(_ data: Data) -> Bool? {
            var index = 3 // start scanning right after magic numbers
            while index < (data.count - 1) {
                // A example of first few bytes of progressive jpeg image:
                // FF D8 FF E0 00 10 4A 46 49 46 00 01 01 00 00 48 00 ...
                //
                // 0xFF, 0xC0 - Start Of Frame (baseline DCT)
                // 0xFF, 0xC2 - Start Of Frame (progressive DCT)
                // https://en.wikipedia.org/wiki/JPEG
                //
                // As an alternative, Image I/O provides facilities to parse
                // JPEG metadata via CGImageSourceCopyPropertiesAtIndex. It is a
                // bit too convoluted to use and most likely slightly less
                // efficient that checking this one special bit directly.
                if data[index] == 0xFF {
                    if data[index + 1] == 0xC2 {
                        return true
                    }
                    if data[index + 1] == 0xC0 {
                        return false // baseline
                    }
                }
                index += 1
            }
            return nil
        }
    }
}
