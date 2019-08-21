// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit
#endif

/// Represents an image request.
public struct ImageRequest {

    // MARK: Parameters of the Request

    internal var urlString: String? {
        return _ref._urlString
    }

    /// The `URLRequest` used for loading an image.
    public var urlRequest: URLRequest {
        get { return _ref.resource.urlRequest }
        set {
            _mutate {
                $0.resource = Resource.urlRequest(newValue)
                $0._urlString = newValue.url?.absoluteString
            }
        }
    }

    /// Processor to be applied to the image. `Decompressor` by default.
    ///
    /// Decompressing compressed image formats (such as JPEG) can significantly
    /// improve drawing performance as it allows a bitmap representation to be
    /// created in a background rather than on the main thread.
    public var processor: AnyImageProcessor? {
        get {
            // Default processor on macOS is nil, on other platforms is Decompressor
            #if !os(macOS)
            return _ref._isDefaultProcessorUsed ? ImageRequest.decompressor : _ref._processor
            #else
            return _ref._isDefaultProcessorUsed ? nil : _ref._processor
            #endif
        }
        set {
            _mutate {
                $0._isDefaultProcessorUsed = false
                $0._processor = newValue
            }
        }
    }

    /// The policy to use when reading or writing images to the memory cache.
    public struct MemoryCacheOptions {
        /// `true` by default.
        public var isReadAllowed = true

        /// `true` by default.
        public var isWriteAllowed = true

        public init() {}
    }

    /// `MemoryCacheOptions()` (read allowed, write allowed) by default.
    public var memoryCacheOptions: MemoryCacheOptions {
        get { return _ref.memoryCacheOptions }
        set { _mutate { $0.memoryCacheOptions = newValue } }
    }

    /// The execution priority of the request.
    public enum Priority: Int, Comparable {
        case veryLow = 0, low, normal, high, veryHigh

        internal var queuePriority: Operation.QueuePriority {
            switch self {
            case .veryLow: return .veryLow
            case .low: return .low
            case .normal: return .normal
            case .high: return .high
            case .veryHigh: return .veryHigh
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// The relative priority of the operation. This value is used to influence
    /// the order in which requests are executed. `.normal` by default.
    public var priority: Priority {
        get { return _ref.priority }
        set { _mutate { $0.priority = newValue }}
    }

    /// Returns a key that compares requests with regards to caching images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared
    /// just by their `URLs`.
    public var cacheKey: AnyHashable? {
        get { return _ref.cacheKey }
        set { _mutate { $0.cacheKey = newValue } }
    }

    /// Returns a key that compares requests with regards to loading images.
    ///
    /// The default key considers two requests equivalent it they have the same
    /// `URLRequests` and the same processors. `URLRequests` are compared by
    /// their `URL`, `cachePolicy`, and `allowsCellularAccess` properties.
    public var loadKey: AnyHashable? {
        get { return _ref.loadKey }
        set { _mutate { $0.loadKey = newValue } }
    }

    /// If decoding is disabled, when the image data is loaded, the pipeline is
    /// not going to create an image from it and will produce the `.decodingFailed`
    /// error instead. `false` by default.
    var isDecodingDisabled: Bool {
        // This only used by `ImagePreheater` right now
        get { return _ref.isDecodingDisabled }
        set { _mutate { $0.isDecodingDisabled = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: Any? {
        get { return _ref.userInfo }
        set { _mutate { $0.userInfo = newValue }}
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    public init(url: URL) {
        _ref = Container(resource: Resource.url(url))
        _ref._urlString = url.absoluteString
        // creating `.absoluteString` takes 50% of time of Request creation,
        // it's still faster than using URLs as cache keys
    }

    /// Initializes a request with the given request.
    public init(urlRequest: URLRequest) {
        _ref = Container(resource: Resource.urlRequest(urlRequest))
        _ref._urlString = urlRequest.url?.absoluteString
    }

    #if !os(macOS)

    /// Initializes a request with the given URL.
    /// - parameter processor: Custom image processer.
    public init<Processor: ImageProcessing>(url: URL, processor: Processor) {
        self.init(url: url)
        self.processor = AnyImageProcessor(processor)
    }

    /// Initializes a request with the given request.
    /// - parameter processor: Custom image processer.
    public init<Processor: ImageProcessing>(urlRequest: URLRequest, processor: Processor) {
        self.init(urlRequest: urlRequest)
        self.processor = AnyImageProcessor(processor)
    }

    /// Initializes a request with the given URL.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(url: URL, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(url: url, processor: ImageDecompressor(
            targetSize: targetSize,
            contentMode: contentMode,
            upscale: upscale
        ))
    }

    /// Initializes a request with the given request.
    /// - parameter targetSize: Size in pixels.
    /// - parameter contentMode: An option for how to resize the image
    /// to the target size.
    public init(urlRequest: URLRequest, targetSize: CGSize, contentMode: ImageDecompressor.ContentMode, upscale: Bool = false) {
        self.init(urlRequest: urlRequest, processor: ImageDecompressor(
            targetSize: targetSize,
            contentMode: contentMode,
            upscale: upscale
        ))
    }

    fileprivate static let decompressor = AnyImageProcessor(ImageDecompressor())

    #endif

    // CoW:

    private var _ref: Container

    private mutating func _mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&_ref) {
            _ref = Container(container: _ref)
        }
        closure(_ref)
    }

    /// Just like many Swift built-in types, `ImageRequest` uses CoW approach to
    /// avoid memberwise retain/releases when `ImageRequest` is passed around.
    private class Container {
        var resource: Resource
        var _urlString: String? // memoized absoluteString
        // true unless user set a custom one, this allows us not to store the
        // default processor anywhere in the `Container` & skip equality tests
        // when the default processor is used
        var _isDefaultProcessorUsed: Bool = true
        var _processor: AnyImageProcessor?
        var memoryCacheOptions = MemoryCacheOptions()
        var priority: ImageRequest.Priority = .normal
        var cacheKey: AnyHashable?
        var loadKey: AnyHashable?
        var isDecodingDisabled: Bool = false
        var userInfo: Any?

        /// Creates a resource with a default processor.
        init(resource: Resource) {
            self.resource = resource
        }

        /// Creates a copy.
        init(container ref: Container) {
            self.resource = ref.resource
            self._urlString = ref._urlString
            self._isDefaultProcessorUsed = ref._isDefaultProcessorUsed
            self._processor = ref._processor
            self.memoryCacheOptions = ref.memoryCacheOptions
            self.priority = ref.priority
            self.cacheKey = ref.cacheKey
            self.loadKey = ref.loadKey
            self.isDecodingDisabled = ref.isDecodingDisabled
            self.userInfo = ref.userInfo
        }
    }

    /// Resource representation (either URL or URLRequest).
    private enum Resource {
        case url(URL)
        case urlRequest(URLRequest)

        var urlRequest: URLRequest {
            switch self {
            case let .url(url): return URLRequest(url: url) // create lazily
            case let .urlRequest(urlRequest): return urlRequest
            }
        }
    }
}

public extension ImageRequest {
    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    mutating func process<P: ImageProcessing>(with processor: P) {
        guard let existing = self.processor else {
            self.processor = AnyImageProcessor(processor)
            return
        }
        // Chain new processor and the existing one.
        self.processor = AnyImageProcessor(ImageProcessorComposition([existing, AnyImageProcessor(processor)]))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    func processed<P: ImageProcessing>(with processor: P) -> ImageRequest {
        var request = self
        request.process(with: processor)
        return request
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    mutating func process<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) {
        process(with: AnonymousImageProcessor<Key>(key, closure))
    }

    /// Appends a processor to the request. You can append arbitrary number of
    /// processors to the request.
    func processed<Key: Hashable>(key: Key, _ closure: @escaping (Image) -> Image?) -> ImageRequest {
        return processed(with: AnonymousImageProcessor<Key>(key, closure))
    }
}

internal extension ImageRequest {
    struct CacheKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request._ref.cacheKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request._ref._urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            let lhs = lhs.request, rhs = rhs.request
            if let lhsCustomKey = lhs._ref.cacheKey, let rhsCustomKey = rhs._ref.cacheKey {
                return lhsCustomKey == rhsCustomKey
            }
            guard lhs._ref._urlString == rhs._ref._urlString else {
                return false
            }
            return (lhs._ref._isDefaultProcessorUsed && rhs._ref._isDefaultProcessorUsed)
                || (lhs.processor == rhs.processor)
        }
    }

    struct LoadKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            if let customKey = request._ref.loadKey {
                hasher.combine(customKey)
            } else {
                hasher.combine(request._ref._urlString?.hashValue ?? 0)
            }
        }

        static func == (lhs: LoadKey, rhs: LoadKey) -> Bool {
            func isEqual(_ lhs: URLRequest, _ rhs: URLRequest) -> Bool {
                return lhs.cachePolicy == rhs.cachePolicy
                    && lhs.allowsCellularAccess == rhs.allowsCellularAccess
            }
            let lhs = lhs.request, rhs = rhs.request
            if let lhsCustomKey = lhs._ref.loadKey, let rhsCustomKey = rhs._ref.loadKey {
                return lhsCustomKey == rhsCustomKey
            }
            return lhs._ref._urlString == rhs._ref._urlString
                && isEqual(lhs.urlRequest, rhs.urlRequest)
        }
    }
}
