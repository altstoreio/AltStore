// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

// Deprecated in 9.4.1
@available(*, deprecated, message: "Renamed to ImagePrefetcher")
public typealias ImagePreheater = ImagePrefetcher

public extension ImagePrefetcher {
    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to startPrefetching")
    func startPreheating(with urls: [URL]) {
        startPrefetching(with: urls)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to startPrefetching")
    func startPreheating(with requests: [ImageRequest]) {
        startPrefetching(with: requests)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating(with urls: [URL]) {
        stopPrefetching(with: urls)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating(with requests: [ImageRequest]) {
        stopPrefetching(with: requests)
    }

    // Deprecated in 9.4.1
    @available(*, deprecated, message: "Renamed to stopPrefetching")
    func stopPreheating() {
        stopPrefetching()
    }
}

public extension ImagePipeline {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Use pipeline.cache[url] instead")
    func cachedImage(for url: URL) -> ImageContainer? {
        cachedImage(for: ImageRequest(url: url))
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Use pipeline.cache[request] instead")
    func cachedImage(for request: ImageRequest) -> ImageContainer? {
        cache[request]
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "If needed, use pipeline.cache.makeDataCacheKey(for:) instead. For original image data, remove the processors from the request. In general, there should be no need to create the keys manually anymore.")
    func cacheKey(for request: ImageRequest, item: DataCacheItem) -> String {
        switch item {
        case .originalImageData:
            var request = request
            request.processors = []
            return request.makeDataCacheKey()
        case .finalImage: return request.makeDataCacheKey()
        }
    }

    @available(*, deprecated, message: "Please use `dataCachePolicy` instead. The recommended policy is the new `.automatic` policy.")
    enum DataCacheItem {
        /// Same as the new `DataCachePolicy.storeOriginalData`
        case originalImageData
        /// Same as the new `DataCachePolicy.storeEncodedImages`
        case finalImage
    }
}

// Deprecated in 10.0.0
@available(*, deprecated, message: "Please use ImagePipelineDelegate")
public protocol ImagePipelineObserving {
    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

// Deprecated in 10.0.0
@available(*, deprecated, message: "Please use the new initializer with `ImageRequest.Options`. It offers the same options and more. For more information see the migration guide at https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%2010%20Migration%20Guide.md#imagerequestoptions.")
public struct ImageRequestOptions {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImagePipeline.Options` instead: `disableMemoryCacheRead`, `disableMemoryCacheWrite`.")
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var isReadAllowed = true

        /// `true` by default.
        public var isWriteAllowed = true

        public init(isReadAllowed: Bool = true, isWriteAllowed: Bool = true) {
            self.isReadAllowed = isReadAllowed
            self.isWriteAllowed = isWriteAllowed
        }
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions: MemoryCacheOptions

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please pass ")
    var cacheKey: AnyHashable?

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "This API does nothing starting with Nuke 10. If you found an issue in coalescing, please report it on GitHub and consider disabling it using ImagePipeline.Configuration.")
    var loadKey: AnyHashable?

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please pass imageId (`ImageRequest.UserInfoKey.imageIdKey`) in the request `userInfo`. The deprecated API does nothing starting with Nuke 10.")
    var filteredURL: AnyHashable?

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please pass the `userInfo` directly to the request. The deprecated API does nothing starting with Nuke 10.")
    var userInfo: [AnyHashable: Any]

    public init(memoryCacheOptions: MemoryCacheOptions = .init(),
                filteredURL: String? = nil,
                cacheKey: AnyHashable? = nil,
                loadKey: AnyHashable? = nil,
                userInfo: [AnyHashable: Any] = [:]) {
        self.memoryCacheOptions = memoryCacheOptions
        self.filteredURL = filteredURL
        self.cacheKey = cacheKey
        self.loadKey = loadKey
        self.userInfo = userInfo
    }
}

public extension ImageRequest {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use the new initializer with `ImageRequest.Options`. It offers the same options and more. For more information see the migration guide at https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%2010%20Migration%20Guide.md#imagerequestoptions.")
    init(url: URL,
         processors: [ImageProcessing] = [],
         cachePolicy: CachePolicy,
         priority: ImageRequest.Priority = .normal,
         options: ImageRequestOptions = .init()) {
        var userInfo = [UserInfoKey: Any]()
        if let filteredURL = options.filteredURL {
            userInfo[.imageIdKey] = filteredURL
        }
        let options = ImageRequest.Options(cachePolicy, options)
        self.init(url: url, processors: processors, priority: priority, options: options, userInfo: userInfo)
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use the new initializer with `ImageRequest.Options`. It offers the same options and more. For more information see the migration guide at https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%2010%20Migration%20Guide.md#imagerequestoptions")
    init(urlRequest: URLRequest,
         processors: [ImageProcessing] = [],
         cachePolicy: CachePolicy,
         priority: ImageRequest.Priority = .normal,
         options: ImageRequestOptions = .init()) {
        var userInfo = [UserInfoKey: Any]()
        if let filteredURL = options.filteredURL {
            userInfo[.imageIdKey] = filteredURL
        }
        let options = ImageRequest.Options(cachePolicy, options)
        self.init(urlRequest: urlRequest, processors: processors, priority: priority, options: options, userInfo: userInfo)
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageRequest.Options` instead, it offers the same options under the same names.")
    var cachePolicy: CachePolicy {
        get {
            if options.contains(.returnCacheDataDontLoad) {
                return .returnCacheDataDontLoad
            }
            if options.contains(.reloadIgnoringCachedData) {
                return .reloadIgnoringCachedData
            }
            return .default
        }
        set {
            options.insert(.init(newValue))
        }
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageRequest.Options` instead, it offers the same options under the same names. And .reloadIgnoringCachedData no longer affects URLCache!")
    enum CachePolicy {
        case `default`
        /// The image should be loaded only from the originating source.
        ///
        /// If you initialize the request with `URLRequest`, make sure to provide
        /// the correct policy in the request too.
        @available(*, deprecated, message: "Please use `ImageRequest.Options` instead. This option is available under the same name: .reloadIgnoringCachedData. This option is also no longer affects URLCache!")
        case reloadIgnoringCachedData

        /// Use existing cache data and fail if no cached data is available.
        @available(*, deprecated, message: "Please use `ImageRequest.Options` instead. This option is available under the same name: .returnCacheDataDontLoad.")
        case returnCacheDataDontLoad
    }
}

private extension ImageRequest.Options {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageRequest.Options` instead, it offers the same options under the same names.")
    init(_ cachePolicy: ImageRequest.CachePolicy) {
        switch cachePolicy {
        case .default:
            self = []
        case .reloadIgnoringCachedData:
            self = .reloadIgnoringCachedData
        case .returnCacheDataDontLoad:
            self = .returnCacheDataDontLoad
        }
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageRequest.Options` instead, it offers the same options under the same names.")
    init(_ cachePolicy: ImageRequest.CachePolicy, _ oldOptions: ImageRequestOptions) {
        var options: ImageRequest.Options = .init(cachePolicy)
        if !oldOptions.memoryCacheOptions.isReadAllowed {
            options.insert(.disableMemoryCacheReads)
        }
        if !oldOptions.memoryCacheOptions.isWriteAllowed {
            options.insert(.disableMemoryCacheWrites)
        }
        self = options
    }
}

public extension ImageDecoders.Default {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageConatainer.UserInfoKey.scanNumber.")
    static let scanNumberKey = "ImageDecoders.Default.scanNumberKey"
}

public extension ImagePipeline.Configuration {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageConatainer` `data` instead. The default image decoder now automatically attaches image data to the ImageContainer type. To learn how to implement animated image support using this new type, see the new Image Formats guide https://github.com/kean/Nuke/blob/9.6.0/Documentation/Guides/image-formats.md. Also see Nuke 10 migration guide https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%2010%20Migration%20Guide.md.")
    static var isAnimatedImageDataEnabled: Bool {
        get { _isAnimatedImageDataEnabled }
        set { _isAnimatedImageDataEnabled = newValue }
    }
}

private var _animatedImageDataAK = "Nuke.AnimatedImageData.AssociatedKey"

extension PlatformImage {
    // Deprecated in 10.0.0
    /// - warning: Soft-deprecated in Nuke 9.0.
    @available(*, deprecated, message: "Please use `ImageConatainer` `data` instead")
    public var animatedImageData: Data? {
        get { _animatedImageData }
        set { _animatedImageData = newValue }
    }

    // Deprecated in 10.0.0
    internal var _animatedImageData: Data? {
        get { objc_getAssociatedObject(self, &_animatedImageDataAK) as? Data }
        set { objc_setAssociatedObject(self, &_animatedImageDataAK, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

extension ImagePipeline.Configuration {
    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use `ImageConfiguration.default` and provide a `dataLoader` afterwards or use a closure-based ImagePipeline initializer.")
    public init(dataLoader: DataLoading = DataLoader(), imageCache: ImageCaching?) {
        self.init(dataLoader: dataLoader)
        self.imageCache = imageCache
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Renamed to isTaskCoalescingEnabled")
    public var isDeduplicationEnabled: Bool {
        get { isTaskCoalescingEnabled }
        set { isTaskCoalescingEnabled = newValue }
    }

    // Deprecated in 10.0.0
    // There is simply no way to make it work consistently across subsystems.
    @available(*, deprecated, message: "Deprecated and will be removed. Please use the new ImageLoadingOptions processors option, or create another way to apply processors by default.")
    public var processors: [ImageProcessing] {
        get { _processors }
        set { _processors = newValue }
    }

    /// Inherits some of the pipeline configuration options like processors.
    func inheritOptions(_ request: ImageRequest) -> ImageRequest {
        guard !_processors.isEmpty, request.processors.isEmpty else {
            return request
        }
        var request = request
        request.processors = _processors
        return request
    }
}

// Deprecated in 10.0.0
@available(*, deprecated, message: "Please use ImageDecoders.Default directly")
public typealias ImageDecoder = ImageDecoders.Default

// Deprecated in 10.0.0
@available(*, deprecated, message: "Please use ImageEncoders.Default directly")
public typealias ImageEncoder = ImageEncoders.Default

// Deprecated in 10.5.0
@available(*, deprecated, message: "Please use AssetType instead")
public typealias ImageType = AssetType

extension ImageDecoders.Empty {
    public init(imageType: AssetType, isProgressive: Bool = false) {
        self = .init(assetType: imageType, isProgressive: isProgressive)
    }
}
