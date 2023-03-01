// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An image decoder.
///
/// A decoder is a one-shot object created for a single image decoding session.
///
/// - note: If you need additional information in the decoder, you can pass
/// anything that you might need from the `ImageDecodingContext`.
public protocol ImageDecoding {
    /// Return `true` if you want the decoding to be performed on the decoding
    /// queue (see `imageDecodingQueue`). If `false`, the decoding will be
    /// performed synchronously on the pipeline operation queue. By default, `true`.
    var isAsynchronous: Bool { get }

    /// Produces an image from the given image data.
    func decode(_ data: Data) -> ImageContainer?

    /// Produces an image from the given partially dowloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, `decode(data:)` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

extension ImageDecoding {
    /// Returns `true` by default.
    public var isAsynchronous: Bool {
        true
    }

    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        nil
    }
}

extension ImageDecoding {
    func decode(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool, cacheType: ImageResponse.CacheType?) -> ImageResponse? {
        func _decode() -> ImageContainer? {
            if isCompleted {
                return decode(data)
            } else {
                return decodePartiallyDownloadedData(data)
            }
        }
        guard let container = autoreleasepool(invoking: _decode) else {
            return nil
        }
        #if !os(macOS)
        if container.userInfo[.isThumbnailKey] == nil {
            ImageDecompression.setDecompressionNeeded(true, for: container.image)
        }
        #endif
        return ImageResponse(container: container, urlResponse: urlResponse, cacheType: cacheType)
    }
}
