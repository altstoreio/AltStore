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

import ImageIO

// MARK: - ImageEncoding

/// An image encoder.
public protocol ImageEncoding {
    /// Encodes the given image.
    func encode(_ image: PlatformImage) -> Data?

    /// An optional method which encodes the given image container.
    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data?
}

public extension ImageEncoding {
    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        self.encode(container.image)
    }
}

/// Image encoding context used when selecting which encoder to use.
public struct ImageEncodingContext {
    public let request: ImageRequest
    public let image: PlatformImage
    public let urlResponse: URLResponse?
}
