// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageDecoders {
    /// A decoder that returns an empty placeholder image and attaches image
    /// data to the image container.
    public struct Empty: ImageDecoding {
        public let isProgressive: Bool
        private let assetType: AssetType?

        public var isAsynchronous: Bool {
            false
        }

        /// Initializes the decoder.
        ///
        /// - Parameters:
        ///   - type: Image type to be associated with an image container.
        ///   `nil` by defalt.
        ///   - isProgressive: If `false`, returns nil for every progressive
        ///   scan. `false` by default.
        public init(assetType: AssetType? = nil, isProgressive: Bool = false) {
            self.assetType = assetType
            self.isProgressive = isProgressive
        }

        public func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            isProgressive ? ImageContainer(image: PlatformImage(), type: assetType, data: data, userInfo: [:]) : nil
        }

        public func decode(_ data: Data) -> ImageContainer? {
            ImageContainer(image: PlatformImage(), type: assetType, data: data, userInfo: [:])
        }
    }
}
