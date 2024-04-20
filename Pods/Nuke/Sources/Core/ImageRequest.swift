// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

#if os(watchOS)
import WatchKit
#endif

#if os(macOS)
import Cocoa
#endif

// MARK: - ImageRequest

/// Represents an image request.
public struct ImageRequest: CustomStringConvertible {

    // MARK: Parameters

    /// Returns the request `URLRequest`.
    ///
    /// Returns `nil` for publisher-based requests.
    public var urlRequest: URLRequest? {
        switch ref.resource {
        case .url(let url): return url.map { URLRequest(url: $0) } // create lazily
        case .urlRequest(let urlRequest): return urlRequest
        case .publisher: return nil
        }
    }

    /// Returns the request `URL`.
    ///
    /// Returns `nil` for publisher-based requests.
    public var url: URL? {
        switch ref.resource {
        case .url(let url): return url
        case .urlRequest(let request): return request.url
        case .publisher: return nil
        }
    }

    /// Returns the ID of the underlying image. For URL-based request, it's an
    /// image URL. For publisher – a custom ID.
    public var imageId: String? {
        switch ref.resource {
        case .url(let url): return url?.absoluteString
        case .urlRequest(let urlRequest): return urlRequest.url?.absoluteString
        case .publisher(let publisher): return publisher.id
        }
    }

    /// The relative priority of the request. The priority affects the order in
    /// which the requests are performed. `.normal` by default.
    public var priority: Priority {
        get { ref.priority }
        set { mutate { $0.priority = newValue } }
    }

    /// Processor to be applied to the image. Empty by default.
    public var processors: [ImageProcessing] {
        get { ref.processors }
        set { mutate { $0.processors = newValue } }
    }

    /// The request options.
    public var options: Options {
        get { ref.options }
        set { mutate { $0.options = newValue } }
    }

    /// Custom info passed alongside the request.
    public var userInfo: [UserInfoKey: Any] {
        get { ref.userInfo ?? [:] }
        set { mutate { $0.userInfo = newValue } }
    }

    /// The priority affecting the order in which the requests are performed.
    public enum Priority: Int, Comparable {
        case veryLow = 0, low, normal, high, veryHigh

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// A key use in `userInfo`.
    public struct UserInfoKey: Hashable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        /// By default, a pipeline uses URLs as unique image identifiers for
        /// caching and task coalescing. You can override this behavior by
        /// providing an `imageIdKey` instead. For example, you can use it to remove
        /// transient query parameters from the request.
        ///
        /// ```
        /// let request = ImageRequest(
        ///     url: URL(string: "http://example.com/image.jpeg?token=123"),
        ///     userInfo: [.imageIdKey: "http://example.com/image.jpeg"]
        /// )
        /// ```
        public static let imageIdKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/imageId"

        /// The image scale to be used. By default, the scale matches the scale
        /// of the current display.
        public static let scaleKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/scale"
        
        /// Specifies whether the pipeline should retreive or generate a thumbnail
        /// instead of a full image. The thumbnail creation is generally significantly
        /// more efficient, especially in terms of memory usage, than image resizing
        /// (`ImageProcessors.Resize`).
        ///
        /// - note: You must be using the default image decoder to make it work.
        public static let thumbnailKey: ImageRequest.UserInfoKey = "github.com/kean/nuke/thumbmnailKey"
    }

    // MARK: Initializers

    /// Initializes a request with the given URL.
    ///
    /// - parameter url: The request URL.
    /// - parameter processors: Processors to be apply to the image. `[]` by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. `[]` by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URL(string: "http://..."),
    ///     processors: [ImageProcessors.Resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(url: URL?,
                processors: [ImageProcessing] = [],
                priority: Priority = .normal,
                options: Options = [],
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.url(url),
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given request.
    ///
    /// - parameter urlRequest: The URLRequest describing the image request.
    /// - parameter processors: Processors to be apply to the image. `[]` by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. `[]` by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     url: URLRequest(url: URL(string: "http://...")),
    ///     processors: [ImageProcessors.Resize(size: imageView.bounds.size)],
    ///     priority: .high
    /// )
    /// ```
    public init(urlRequest: URLRequest,
                processors: [ImageProcessing] = [],
                priority: Priority = .normal,
                options: Options = [],
                userInfo: [UserInfoKey: Any]? = nil) {
        self.ref = Container(
            resource: Resource.urlRequest(urlRequest),
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    /// Initializes a request with the given data publisher.
    ///
    /// - parameter id: Uniquely identifies the image data.
    /// - parameter data: A data publisher to be used for fetching image data.
    /// - parameter processors: Processors to be apply to the image. `[]` by default.
    /// - parameter priority: The priority of the request, `.normal` by default.
    /// - parameter options: Image loading options. `[]` by default.
    /// - parameter userInfo: Custom info passed alongside the request. `nil` by default.
    ///
    /// For example, here is how you can use it with Photos framework (the
    /// `imageDataPublisher()` API is a convenience extension).
    ///
    /// ```swift
    /// let request = ImageRequest(
    ///     id: asset.localIdentifier,
    ///     data: PHAssetManager.imageDataPublisher(for: asset)
    /// )
    /// ```
    ///
    /// - warning: If you don't want data to be stored in the disk cache, make
    /// sure to create a pipeline without it or disable it on a per-request basis.
    /// You can also disable it dynamically using `ImagePipelineDelegate`.
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    public init<P>(id: String, data: P,
                   processors: [ImageProcessing] = [],
                   priority: Priority = .normal,
                   options: Options = [],
                   userInfo: [UserInfoKey: Any]? = nil) where P: Publisher, P.Output == Data {
        // It could technically be implemented without any special change to the
        // pipeline by using a custom DataLoader, disabling resumable data, and
        // passing a publisher in the request userInfo.
        self.ref = Container(
            resource: .publisher(DataPublisher(id: id, data)),
            processors: processors,
            priority: priority,
            options: options,
            userInfo: userInfo
        )
    }

    // MARK: Options

    /// Image request options.
    public struct Options: OptionSet, Hashable {
        /// Returns a raw value.
        public let rawValue: UInt16

        /// Initialializes options with a given raw values.
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        /// Disables memory cache reads (`ImageCaching`).
        public static let disableMemoryCacheReads = Options(rawValue: 1 << 0)

        /// Disables memory cache writes (`ImageCaching`).
        public static let disableMemoryCacheWrites = Options(rawValue: 1 << 1)

        /// Disables both memory cache reads and writes (`ImageCaching`).
        public static let disableMemoryCache: Options = [.disableMemoryCacheReads, .disableMemoryCacheWrites]

        /// Disables disk cache reads (`DataCaching`).
        public static let disableDiskCacheReads = Options(rawValue: 1 << 2)

        /// Disables disk cache writes (`DataCaching`).
        public static let disableDiskCacheWrites = Options(rawValue: 1 << 3)

        /// Disables both disk cache reads and writes (`DataCaching`).
        public static let disableDiskCache: Options = [.disableDiskCacheReads, .disableDiskCacheWrites]

        /// The image should be loaded only from the originating source.
        ///
        /// This option only works `ImageCaching` and `DataCaching`, but not
        /// `URLCache`. If you want to ignore `URLCache`, initialize the request
        /// with `URLRequest` with the respective policy
        public static let reloadIgnoringCachedData: Options = [.disableMemoryCacheReads, .disableDiskCacheReads]

        /// Use existing cache data and fail if no cached data is available.
        public static let returnCacheDataDontLoad = Options(rawValue: 1 << 4)
    }
    
    /// Thumbnail options.
    ///
    /// For more info, see https://developer.apple.com/documentation/imageio/cgimagesource/image_source_option_dictionary_keys
    public struct ThumbnailOptions: Hashable {
        /// The maximum width and height in pixels of a thumbnail. If this key
        /// is not specified, the width and height of a thumbnail is not limited
        /// and thumbnails may be as big as the image itself.
        public var maxPixelSize: CGFloat
                
        /// Whether a thumbnail should be automatically created for an image if
        /// a thumbnail isn't present in the image source file. The thumbnail is
        /// created from the full image, subject to the limit specified by
        /// `maxPixelSize`.
        ///
        /// By default, `true`.
        public var createThumbnailFromImageIfAbsent = true
        
        /// Whether a thumbnail should be created from the full image even if a
        /// thumbnail is present in the image source file. The thumbnail is created
        /// from the full image, subject to the limit specified by
        /// `maxPixelSize`.
        ///
        /// By default, `true`.
        public var createThumbnailFromImageAlways = true
        
        /// Whether the thumbnail should be rotated and scaled according to the
        /// orientation and pixel aspect ratio of the full image.
        ///
        /// By default, `true`.
        public var createThumbnailWithTransform = true
    
        /// Specifies whether image decoding and caching should happen at image
        /// creation time.
        ///
        /// By default, `true`.
        public var shouldCacheImmediately = true
        
        public init(maxPixelSize: CGFloat,
                    createThumbnailFromImageIfAbsent: Bool = true,
                    createThumbnailFromImageAlways: Bool = true,
                    createThumbnailWithTransform: Bool = true,
                    shouldCacheImmediately: Bool = true) {
            self.maxPixelSize = maxPixelSize
            self.createThumbnailFromImageIfAbsent = createThumbnailFromImageIfAbsent
            self.createThumbnailFromImageAlways = createThumbnailFromImageAlways
            self.createThumbnailWithTransform = createThumbnailWithTransform
            self.shouldCacheImmediately = shouldCacheImmediately
        }
        
        var identifier: String {
            "com.github/kean/nuke/thumbnail?mxs=\(maxPixelSize),options=\(createThumbnailFromImageIfAbsent)\(createThumbnailFromImageAlways)\(createThumbnailWithTransform)\(shouldCacheImmediately)"
        }
    }

    // MARK: Internal

    private(set) var ref: Container

    private mutating func mutate(_ closure: (Container) -> Void) {
        if !isKnownUniquelyReferenced(&ref) {
            ref = Container(ref)
        }
        closure(ref)
    }

    /// Just like many Swift built-in types, `ImageRequest` uses CoW approach to
    /// avoid memberwise retain/releases when `ImageRequest` is passed around.
    final class Container {
        // It's benefitial to put resource before priority and options because
        // of the resource size/stride of 9/16. Priority (1 byte) and Options
        // (2 bytes) slot just right in the remaining space.
        let resource: Resource
        fileprivate(set) var priority: Priority
        fileprivate(set) var options: Options
        fileprivate(set) var processors: [ImageProcessing]
        fileprivate(set) var userInfo: [UserInfoKey: Any]?
        // After trimming down the request size, it is no longer
        // as beneficial using CoW for ImageRequest, but there
        // still is a small but measurable difference.

        deinit {
            #if TRACK_ALLOCATIONS
            Allocations.decrement("ImageRequest.Container")
            #endif
        }

        /// Creates a resource with a default processor.
        init(resource: Resource, processors: [ImageProcessing], priority: Priority, options: Options, userInfo: [UserInfoKey: Any]?) {
            self.resource = resource
            self.processors = processors
            self.priority = priority
            self.options = options
            self.userInfo = userInfo

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }

        /// Creates a copy.
        init(_ ref: Container) {
            self.resource = ref.resource
            self.processors = ref.processors
            self.priority = ref.priority
            self.options = ref.options
            self.userInfo = ref.userInfo

            #if TRACK_ALLOCATIONS
            Allocations.increment("ImageRequest.Container")
            #endif
        }
    }

    // Every case takes 8 bytes and the enum 9 bytes overall (use stride!)
    enum Resource: CustomStringConvertible {
        case url(URL?)
        case urlRequest(URLRequest)
        case publisher(DataPublisher)

        var description: String {
            switch self {
            case .url(let url): return "\(url?.absoluteString ?? "nil")"
            case .urlRequest(let urlRequest): return "\(urlRequest)"
            case .publisher(let data): return "\(data)"
            }
        }
    }

    public var description: String {
        "ImageRequest(resource: \(ref.resource), priority: \(priority), processors: \(processors), options: \(options), userInfo: \(userInfo))"
    }

    func withProcessors(_ processors: [ImageProcessing]) -> ImageRequest {
        var request = self
        request.processors = processors
        return request
    }

    var preferredImageId: String {
        if let imageId = ref.userInfo?[.imageIdKey] as? String {
            return imageId
        }
        return imageId ?? ""
    }
    
    var thubmnail: ThumbnailOptions? {
        ref.userInfo?[.thumbnailKey] as? ThumbnailOptions
    }
    
    var scale: CGFloat? {
        guard let scale = ref.userInfo?[.scaleKey] as? NSNumber else {
            return nil
        }
        return CGFloat(scale.floatValue)
    }

    var publisher: DataPublisher? {
        guard case .publisher(let publisher) = ref.resource else {
            return nil
        }
        return publisher
    }
}

// MARK: - ImageRequestConvertible

/// Represents a type that can be converted to an `ImageRequest`.
public protocol ImageRequestConvertible {
    func asImageRequest() -> ImageRequest
}

extension ImageRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        self
    }
}

extension URL: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(url: self)
    }
}

extension Optional: ImageRequestConvertible where Wrapped == URL {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(url: self)
    }
}

extension URLRequest: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(urlRequest: self)
    }
}

extension String: ImageRequestConvertible {
    public func asImageRequest() -> ImageRequest {
        ImageRequest(url: URL(string: self))
    }
}
