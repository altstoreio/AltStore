// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// In-memory image cache.
///
/// The implementation must be thread safe.
public protocol ImageCaching: AnyObject {
    /// Access the image cached for the given request.
    subscript(key: ImageCacheKey) -> ImageContainer? { get set }

    /// Removes all caches items.
    func removeAll()
}

/// An opaque container that acts as a cache key.
///
/// In general, you don't construct it directly, and use `ImagePipeline` or `ImagePipeline.Cache` APIs.
public struct ImageCacheKey: Hashable {
    let key: Inner

    // This is faster than using AnyHashable (and it shows in performance tests).
    enum Inner: Hashable {
        case custom(String)
        case `default`(CacheKey)
    }

    public init(key: String) {
        self.key = .custom(key)
    }

    init(request: ImageRequest) {
        self.key = .default(request.makeImageCacheKey())
    }
}

public extension ImageCaching {
    /// A convenience API for getting an image for the given request.
    ///
    /// - warning: If you provide a custom key using `ImagePipelineDelegate`, use
    /// `ImagePipeline.Cache` instead.
    subscript(request: ImageRequestConvertible) -> ImageContainer? {
        get { self[ImageCacheKey(request: request.asImageRequest())] }
        set { self[ImageCacheKey(request: request.asImageRequest())] = newValue }
    }
}
