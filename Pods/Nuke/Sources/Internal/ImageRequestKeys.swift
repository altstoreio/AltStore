// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageRequest {

    // MARK: - Cache Keys

    /// A key for processed image in memory cache.
    func makeImageCacheKey() -> CacheKey {
        CacheKey(self)
    }

    /// A key for processed image data in disk cache.
    func makeDataCacheKey() -> String {
        "\(preferredImageId)\(thubmnail?.identifier ?? "")\(ImageProcessors.Composition(processors).identifier)"
    }

    // MARK: - Load Keys

    /// A key for deduplicating operations for fetching the processed image.
    func makeImageLoadKey() -> ImageLoadKey {
        ImageLoadKey(self)
    }
    
    /// A key for deduplicating operations for fetching the decoded image.
    func makeDecodedImageLoadKey() -> DecodedImageLoadKey {
        DecodedImageLoadKey(self)
    }
    
    /// A key for deduplicating operations for fetching the original image.
    func makeDataLoadKey() -> DataLoadKey {
        DataLoadKey(self)
    }
}

/// Uniquely identifies a cache processed image.
struct CacheKey: Hashable {
    private let imageId: String?
    private let thumbnail: ImageRequest.ThumbnailOptions?
    private let processors: [ImageProcessing]

    init(_ request: ImageRequest) {
        self.imageId = request.preferredImageId
        self.thumbnail = request.thubmnail
        self.processors = request.ref.processors
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(imageId)
        hasher.combine(thumbnail)
        hasher.combine(processors.count)
    }

    static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
        lhs.imageId == rhs.imageId && lhs.thumbnail == rhs.thumbnail && lhs.processors == rhs.processors
    }
}

/// Uniquely identifies a task of retrieving the processed image.
struct ImageLoadKey: Hashable {
    let cacheKey: CacheKey
    let options: ImageRequest.Options
    let thumbnail: ImageRequest.ThumbnailOptions?
    let loadKey: DataLoadKey

    init(_ request: ImageRequest) {
        self.cacheKey = CacheKey(request)
        self.options = request.options
        self.thumbnail = request.thubmnail
        self.loadKey = DataLoadKey(request)
    }
}

/// Uniquely identifies a task of retrieving the decoded image.
struct DecodedImageLoadKey: Hashable {
    let dataLoadKey: DataLoadKey
    let thumbnail: ImageRequest.ThumbnailOptions?
    
    init(_ request: ImageRequest) {
        self.dataLoadKey = DataLoadKey(request)
        self.thumbnail = request.thubmnail
    }
}

/// Uniquely identifies a task of retrieving the original image dataa.
struct DataLoadKey: Hashable {
    private let imageId: String?
    private let cachePolicy: URLRequest.CachePolicy
    private let allowsCellularAccess: Bool

    init(_ request: ImageRequest) {
        self.imageId = request.imageId
        switch request.ref.resource {
        case .url, .publisher:
            self.cachePolicy = .useProtocolCachePolicy
            self.allowsCellularAccess = true
        case let .urlRequest(urlRequest):
            self.cachePolicy = urlRequest.cachePolicy
            self.allowsCellularAccess = urlRequest.allowsCellularAccess
        }
    }
}

struct ImageProcessingKey: Equatable, Hashable {
    let imageId: ObjectIdentifier
    let processorId: AnyHashable

    init(image: ImageResponse, processor: ImageProcessing) {
        self.imageId = ObjectIdentifier(image.image)
        self.processorId = processor.hashableIdentifier
    }
}
