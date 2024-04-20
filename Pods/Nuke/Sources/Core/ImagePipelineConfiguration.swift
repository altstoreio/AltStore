// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// MARK: - ImagePipeline.Configuration

extension ImagePipeline {
    /// The pipeline configuration.
    public struct Configuration {
        // MARK: - Dependencies

        /// Image cache used by the pipeline.
        public var imageCache: ImageCaching? {
            // This exists simply to ensure we don't init ImageCache.shared if the
            // user provides their own instance.
            get { isCustomImageCacheProvided ? customImageCache : ImageCache.shared }
            set {
                customImageCache = newValue
                isCustomImageCacheProvided = true
            }
        }
        private var customImageCache: ImageCaching?

        /// Data loader used by the pipeline.
        public var dataLoader: DataLoading

        /// Data cache used by the pipeline.
        public var dataCache: DataCaching?

        /// Default implementation uses shared `ImageDecoderRegistry` to create
        /// a decoder that matches the context.
        public var makeImageDecoder: (ImageDecodingContext) -> ImageDecoding? = ImageDecoderRegistry.shared.decoder(for:)

        /// Returns `ImageEncoders.Default()` by default.
        public var makeImageEncoder: (ImageEncodingContext) -> ImageEncoding = { _ in
            ImageEncoders.Default()
        }

        // MARK: - Operation Queues

        /// Data loading queue. Default maximum concurrent task count is 6.
        public var dataLoadingQueue = OperationQueue(maxConcurrentCount: 6)

        /// Data caching queue. Default maximum concurrent task count is 2.
        public var dataCachingQueue = OperationQueue(maxConcurrentCount: 2)

        /// Image decoding queue. Default maximum concurrent task count is 1.
        public var imageDecodingQueue = OperationQueue(maxConcurrentCount: 1)

        /// Image encoding queue. Default maximum concurrent task count is 1.
        public var imageEncodingQueue = OperationQueue(maxConcurrentCount: 1)

        /// Image processing queue. Default maximum concurrent task count is 2.
        public var imageProcessingQueue = OperationQueue(maxConcurrentCount: 2)

        #if !os(macOS)
        /// Image decompressing queue. Default maximum concurrent task count is 2.
        public var imageDecompressingQueue = OperationQueue(maxConcurrentCount: 2)
        #endif

        // MARK: - Options
        
        /// A queue on which all callbacks, like `progress` and `completion`
        /// callbacks are called. `.main` by default.
        public var callbackQueue = DispatchQueue.main

        #if !os(macOS)
        /// Decompresses the loaded images. `true` by default.
        ///
        /// Decompressing compressed image formats (such as JPEG) can significantly
        /// improve drawing performance as it allows a bitmap representation to be
        /// created in a background rather than on the main thread.
        public var isDecompressionEnabled = true
        #endif

        /// `.storeOriginalData` by default.
        public var dataCachePolicy = DataCachePolicy.storeOriginalData

        /// Determines what images are stored in the disk cache.
        public enum DataCachePolicy {
            /// For requests with processors, encode and store processed images.
            /// For requests with no processors, store original image data, unless
            /// the resource is local (file:// or data:// scheme is used).
            ///
            /// - warning: With this policy, the pipeline `loadData()` method
            /// will not store the images in the disk cache for requests with
            /// any processors applied – this method only loads data and doesn't
            /// decode images.
            case automatic

            /// For all requests, only store the original image data, unless
            /// the resource is local (file:// or data:// scheme is used).
            case storeOriginalData

            /// For all requests, encode and store decoded images after all
            /// processors are applied.
            ///
            /// - note: This is useful if you want to store images in a format
            /// different than provided by a server, e.g. decompressed. In other
            /// scenarios, consider using `.automatic` policy instead.
            ///
            /// - warning: With this policy, the pipeline `loadData()` method
            /// will not store the images in the disk cache – this method only
            /// loads data and doesn't decode images.
            case storeEncodedImages

            /// For requests with processors, encode and store processed images.
            /// For all requests, store original image data.
            case storeAll
        }

        // Deprecated in 10.0.0
        @available(*, deprecated, message: "Please use `dataCachePolicy` instead.")
        public var dataCacheOptions: DataCacheOptions = DataCacheOptions() {
            didSet {
                let items = dataCacheOptions.storedItems
                if items == [.finalImage] {
                    dataCachePolicy = .storeEncodedImages
                } else if items == [.originalImageData] {
                    dataCachePolicy = .storeOriginalData
                } else if items == [.finalImage, .originalImageData] {
                    dataCachePolicy = .storeAll
                }
            }
        }

        // Deprecated in 10.0.0
        @available(*, deprecated, message: "Please use `dataCachePolicy` instead. The recommended policy is the new `.automatic` policy.")
        public struct DataCacheOptions {
            public var storedItems: Set<DataCacheItem> = [.originalImageData]
        }

        // Deprecated in 10.0.0
        var _processors: [ImageProcessing] = []

        /// `true` by default. If `true` the pipeline avoids duplicated work when
        /// loading images. The work only gets cancelled when all the registered
        /// requests are. The pipeline also automatically manages the priority of the
        /// deduplicated work.
        ///
        /// Let's take these two requests for example:
        ///
        /// ```swift
        /// let url = URL(string: "http://example.com/image")
        /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
        ///     ImageProcessors.Resize(size: CGSize(width: 44, height: 44)),
        ///     ImageProcessors.GaussianBlur(radius: 8)
        /// ]))
        /// pipeline.loadImage(with: ImageRequest(url: url, processors: [
        ///     ImageProcessors.Resize(size: CGSize(width: 44, height: 44))
        /// ]))
        /// ```
        ///
        /// Nuke will load the image data only once, resize the image once and
        /// apply the blur also only once. There is no duplicated work done at
        /// any stage.
        public var isTaskCoalescingEnabled = true

        /// `true` by default. If `true` the pipeline will rate limit requests
        /// to prevent trashing of the underlying systems (e.g. `URLSession`).
        /// The rate limiter only comes into play when the requests are started
        /// and cancelled at a high rate (e.g. scrolling through a collection view).
        public var isRateLimiterEnabled = true

        /// `false` by default. If `true` the pipeline will try to produce a new
        /// image each time it receives a new portion of data from data loader.
        /// The decoder used by the image loading session determines whether
        /// to produce a partial image or not. The default image decoder
        /// (`ImageDecoder`) supports progressive JPEG decoding.
        public var isProgressiveDecodingEnabled = true

        /// `false` by default. If `true`, the pipeline will store all of the
        /// progressively generated previews in the memory cache. All of the
        /// previews have `isPreview` flag set to `true`.
        public var isStoringPreviewsInMemoryCache = true

        /// If the data task is terminated (either because of a failure or a
        /// cancellation) and the image was partially loaded, the next load will
        /// resume where it left off. Supports both validators (`ETag`,
        /// `Last-Modified`). Resumable downloads are enabled by default.
        public var isResumableDataEnabled = true

        // MARK: - Options (Shared)

        /// If `true` pipeline will detect GIFs and set `animatedImageData`
        /// (`UIImage` property). It will also disable processing of such images,
        /// and alter the way cache cost is calculated. However, this will not
        /// enable actual animated image rendering. To do that take a look at
        /// satellite projects (FLAnimatedImage and Gifu plugins for Nuke).
        /// `false` by default (to preserve resources).
        static var _isAnimatedImageDataEnabled = false

        /// `false` by default. If `true`, enables `os_signpost` logging for
        /// measuring performance. You can visually see all the performance
        /// metrics in `os_signpost` Instrument. For more information see
        /// https://developer.apple.com/documentation/os/logging and
        /// https://developer.apple.com/videos/play/wwdc2018/405/.
        public static var isSignpostLoggingEnabled = false {
            didSet {
                log = isSignpostLoggingEnabled ?
                    OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading") :
                    .disabled
            }
        }

        private var isCustomImageCacheProvided = false

        var debugIsSyncImageEncoding = false
        
        // MARK: - Initializer

        /// Instantiates a default pipeline configuration.
        ///
        /// - parameter dataLoader: `DataLoader()` by default.
        public init(dataLoader: DataLoading = DataLoader()) {
            self.dataLoader = dataLoader
        }

        /// A configuration with a `DataLoader` with an HTTP disk cache (`URLCache`)
        /// with a size limit of 150 MB.
        public static var withURLCache: Configuration { Configuration() }

        /// A configuration with an aggressive disk cache (`DataCache`) with a
        /// size limit of 150 MB. An HTTP cache (`URLCache`) is disabled.
        public static var withDataCache: Configuration {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()

            var config = Configuration()
            config.dataLoader = dataLoader
            config.dataCache = try? DataCache(name: "com.github.kean.Nuke.DataCache")

            return config
        }
    }
}
