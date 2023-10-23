// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Provides a set of convenience APIs for managing the pipeline cache layers,
    /// including `ImageCaching` (memory cache) and `DataCaching` (disk cache).
    ///
    /// - warning: This class doesn't work with a `URLCache`. For more info,
    /// see ["Caching"](https://kean.blog/nuke/guides/caching).
    ///
    /// Thread-safe.
    public struct Cache {
        let pipeline: ImagePipeline
        private var configuration: ImagePipeline.Configuration { pipeline.configuration }

        // MARK: Subscript (Memory Cache)

        /// Returns an image from the memory cache for the given request.
        public subscript(request: ImageRequestConvertible) -> ImageContainer? {
            get { self[request.asImageRequest()] }
            nonmutating set { self[request.asImageRequest()] = newValue }
        }

        subscript(request: ImageRequest) -> ImageContainer? {
            get {
                cachedImageFromMemoryCache(for: request)
            }
            nonmutating set {
                if let image = newValue {
                    storeCachedImageInMemoryCache(image, for: request)
                } else {
                    removeCachedImageFromMemoryCache(for: request)
                }
            }
        }

        // MARK: Cached Images

        /// Returns a cached image any of the caches.
        ///
        /// - note: Respects request options such as `cachePolicy`.
        ///
        /// - parameter request: The request. Make sure to remove the processors
        /// if you want to retrieve an original image (if it's stored).
        /// - parameter caches: `[.all]`, by default.
        public func cachedImage(for request: ImageRequestConvertible, caches: Caches = [.all]) -> ImageContainer? {
            let request = request.asImageRequest()
            if caches.contains(.memory) {
                if let image = cachedImageFromMemoryCache(for: request) {
                    return image
                }
            }
            if caches.contains(.disk) {
                if let data = cachedData(for: request),
                   let image = decodeImageData(data, for: request) {
                    return image
                }
            }
            return nil
        }

        /// Stores the image in all caches. To store image in the disk cache, it
        /// will be encoded (see `ImageEncoding`)
        ///
        /// - note: Respects request cache options.
        ///
        /// - note: Default `DiskCache` stores data asynchronously, so it's safe
        /// to call this method even from the main thread.
        ///
        /// - note: Image previews are not stored.
        ///
        /// - parameter request: The request. Make sure to remove the processors
        /// if you want to retrieve an original image (if it's stored).
        /// - parameter caches: `[.all]`, by default.
        public func storeCachedImage(_ image: ImageContainer, for request: ImageRequestConvertible, caches: Caches = [.all]) {
            let request = request.asImageRequest()
            if caches.contains(.memory) {
                storeCachedImageInMemoryCache(image, for: request)
            }
            if caches.contains(.disk) {
                if let data = encodeImage(image, for: request) {
                    storeCachedData(data, for: request)
                }
            }
        }

        /// Removes the image from all caches.
        public func removeCachedImage(for request: ImageRequestConvertible, caches: Caches = [.all]) {
            let request = request.asImageRequest()
            if caches.contains(.memory) {
                removeCachedImageFromMemoryCache(for: request)
            }
            if caches.contains(.disk) {
                removeCachedData(for: request)
            }
        }

        /// Returns `true` if any of the caches contain the image.
        public func containsCachedImage(for request: ImageRequestConvertible, caches: Caches = [.all]) -> Bool {
            let request = request.asImageRequest()
            if caches.contains(.memory) && cachedImageFromMemoryCache(for: request) != nil {
                return true
            }
            if caches.contains(.disk), let dataCache = dataCache(for: request) {
                let key = makeDataCacheKey(for: request)
                return dataCache.containsData(for: key)
            }
            return false
        }

        private func cachedImageFromMemoryCache(for request: ImageRequest) -> ImageContainer? {
            guard !request.options.contains(.disableMemoryCacheReads) else {
                return nil
            }
            let key = makeImageCacheKey(for: request)
            if let imageCache = pipeline.imageCache {
                return imageCache[key] // Fast path for a default cache (no protocol call)
            }
            return configuration.imageCache?[key]
        }

        private func storeCachedImageInMemoryCache(_ image: ImageContainer, for request: ImageRequest) {
            guard !request.options.contains(.disableMemoryCacheWrites) else {
                return
            }
            guard !image.isPreview || configuration.isStoringPreviewsInMemoryCache else {
                return
            }
            let key = makeImageCacheKey(for: request)
            configuration.imageCache?[key] = image
        }

        private func removeCachedImageFromMemoryCache(for request: ImageRequest) {
            let key = makeImageCacheKey(for: request)
            configuration.imageCache?[key] = nil
        }

        // MARK: Cached Data

        /// Returns cached data for the given request.
        public func cachedData(for request: ImageRequestConvertible) -> Data? {
            let request = request.asImageRequest()
            guard !request.options.contains(.disableDiskCacheReads) else {
                return nil
            }
            guard let dataCache = dataCache(for: request) else {
                return nil
            }
            let key = makeDataCacheKey(for: request)
            return dataCache.cachedData(for: key)
        }

        /// Stores data for the given request.
        ///
        /// - note: Default `DiskCache` stores data asynchronously, so it's safe
        /// to call this method even from the main thread.
        public func storeCachedData(_ data: Data, for request: ImageRequestConvertible) {
            let request = request.asImageRequest()
            guard let dataCache = dataCache(for: request),
                  !request.options.contains(.disableDiskCacheWrites) else {
                return
            }
            let key = makeDataCacheKey(for: request)
            dataCache.storeData(data, for: key)
        }

        /// Returns true if the data cache contains data for the given image
        public func containsData(for request: ImageRequestConvertible) -> Bool {
            let request = request.asImageRequest()
            guard let dataCache = dataCache(for: request) else {
                return false
            }
            return dataCache.containsData(for: makeDataCacheKey(for: request))
        }

        /// Removes cached data for the given request.
        public func removeCachedData(for request: ImageRequestConvertible) {
            let request = request.asImageRequest()
            guard let dataCache = dataCache(for: request) else {
                return
            }
            let key = makeDataCacheKey(for: request)
            dataCache.removeData(for: key)
        }

        // MARK: Keys

        /// Returns image cache (memory cache) key for the given request.
        public func makeImageCacheKey(for request: ImageRequestConvertible) -> ImageCacheKey {
            makeImageCacheKey(for: request.asImageRequest())
        }

        func makeImageCacheKey(for request: ImageRequest) -> ImageCacheKey {
            if let customKey = pipeline.delegate.cacheKey(for: request, pipeline: pipeline) {
                return ImageCacheKey(key: customKey)
            }
            return ImageCacheKey(request: request) // Use the default key
        }

        /// Returns data cache (disk cache) key for the given request.
        public func makeDataCacheKey(for request: ImageRequestConvertible) -> String {
            makeDataCacheKey(for: request.asImageRequest())
        }

        func makeDataCacheKey(for request: ImageRequest) -> String {
            if let customKey = pipeline.delegate.cacheKey(for: request, pipeline: pipeline) {
                return customKey
            }
            return request.makeDataCacheKey() // Use the default key
        }

        // MARK: Misc

        /// Removes both images and data from all cache layes.
        public func removeAll(caches: Caches = [.all]) {
            if caches.contains(.memory) {
                configuration.imageCache?.removeAll()
            }
            if caches.contains(.disk) {
                configuration.dataCache?.removeAll()
            }
        }

        // MARK: Private

        private func decodeImageData(_ data: Data, for request: ImageRequest) -> ImageContainer? {
            let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
            guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
                return nil
            }
            return decoder.decode(data, urlResponse: nil, isCompleted: true, cacheType: .disk)?.container
        }

        private func encodeImage(_ image: ImageContainer, for request: ImageRequest) -> Data? {
            let context = ImageEncodingContext(request: request, image: image.image, urlResponse: nil)
            let encoder = pipeline.delegate.imageEncoder(for: context, pipeline: pipeline)
            return encoder.encode(image, context: context)
        }

        private func dataCache(for request: ImageRequest) -> DataCaching? {
            pipeline.delegate.dataCache(for: request, pipeline: pipeline)
        }

        // MARK: Options

        /// Describes a set of cache layers to use.
        public struct Caches: OptionSet {
            public let rawValue: Int
            public init(rawValue: Int) {
                self.rawValue = rawValue
            }

            public static let memory = Caches(rawValue: 1 << 0)
            public static let disk = Caches(rawValue: 1 << 1)
            public static let all: Caches = [.memory, .disk]
        }
    }
}
