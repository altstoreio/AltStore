// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

struct ImageDecompression {

    static func decompress(image: PlatformImage) -> PlatformImage {
        image.decompressed() ?? image
    }

    // MARK: Managing Decompression State

    static var isDecompressionNeededAK = "ImageDecompressor.isDecompressionNeeded.AssociatedKey"

    static func setDecompressionNeeded(_ isDecompressionNeeded: Bool, for image: PlatformImage) {
        objc_setAssociatedObject(image, &isDecompressionNeededAK, isDecompressionNeeded, .OBJC_ASSOCIATION_RETAIN)
    }

    static func isDecompressionNeeded(for image: PlatformImage) -> Bool? {
        objc_getAssociatedObject(image, &isDecompressionNeededAK) as? Bool
    }
}
