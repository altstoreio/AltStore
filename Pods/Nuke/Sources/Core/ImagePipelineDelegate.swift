// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A delegate that allows you to customize the pipleine on a per-request basis.
///
/// - warning: The delegate methods are performed on the pipeline queue in the
/// background.
public protocol ImagePipelineDelegate: AnyObject {
    // MARK: Configuration

    /// Returns data loader for the given request.
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> DataLoading

    /// Retuns disk cache for the given request. Return `nil` to prevent cache
    /// reads and writes.
    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> DataCaching?

    /// Returns image decoder for the given context.
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImageDecoding?

    /// Returns image encoder for the given context.
    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> ImageEncoding

    // MARK: Caching

    /// Returns a cache key identifying the image produced for the given request
    /// (including image processors).
    ///
    /// Return `nil` to use a default key.
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String?

    /// Gets called when the pipeline is about to save data for the given request.
    /// The implementation must call the completion closure passing `non-nil` data
    /// to enable caching or `nil` to prevent it.
    ///
    /// This method calls only if the request parameters and data caching policy
    /// of the pipeline already allow caching.
    ///
    /// - parameter data: Either the original data or the encoded image in case
    /// of storing a processed or re-encoded image.
    /// - parameter image: Non-nil in case storing an encoded image.
    /// - parameter request: The request for which image is being stored.
    /// - parameter completion: The implementation must call the completion closure
    /// passing `non-nil` data to enable caching or `nil` to prevent it. You can
    /// safely call it synchronously. The callback gets called on the background
    /// thread.
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void)

    // MARK: Monitoring

    /// Delivers the events produced by the image tasks started via `loadImage` method.
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent)
}

public extension ImagePipelineDelegate {
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> DataLoading {
        pipeline.configuration.dataLoader
    }

    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> DataCaching? {
        pipeline.configuration.dataCache
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImageDecoding? {
        pipeline.configuration.makeImageDecoder(context)
    }

    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> ImageEncoding {
        pipeline.configuration.makeImageEncoder(context)
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        nil
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(data)
    }

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        // Do nothing
    }
}

/// An image task event sent by the pipeline.
public enum ImageTaskEvent {
    case started
    case cancelled
    case priorityUpdated(priority: ImageRequest.Priority)
    case intermediateResponseReceived(response: ImageResponse)
    case progressUpdated(completedUnitCount: Int64, totalUnitCount: Int64)
    case completed(result: Result<ImageResponse, ImagePipeline.Error>)
}

extension ImageTaskEvent {
    init(_ event: AsyncTask<ImageResponse, ImagePipeline.Error>.Event) {
        switch event {
        case let .error(error):
            self = .completed(result: .failure(error))
        case let .value(response, isCompleted):
            if isCompleted {
                self = .completed(result: .success(response))
            } else {
                self = .intermediateResponseReceived(response: response)
            }
        case let .progress(progress):
            self = .progressUpdated(completedUnitCount: progress.completed, totalUnitCount: progress.total)
        }
    }
}

final class ImagePipelineDefaultDelegate: ImagePipelineDelegate {}
