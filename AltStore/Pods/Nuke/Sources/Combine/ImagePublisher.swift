// The MIT License (MIT)
//
// Copyright (c) 2020-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public extension ImagePipeline {
    /// Returns a publisher which starts a new `ImageTask` when a subscriber is added.
    ///
    /// - note: For more information, see `ImagePublisher`.
    func imagePublisher(with request: ImageRequestConvertible) -> ImagePublisher {
        ImagePublisher(request: request.asImageRequest(), pipeline: self)
    }
}

/// A publisher that starts a new `ImageTask` when a subscriber is added.
///
/// If the requested image is available in the memory cache, the value is
/// delivered immediately. When the subscription is cancelled, the task also
/// gets cancelled.
///
/// - note: In case the pipeline has `isProgressiveDecodingEnabled` option enabled
/// and the image being downloaded supports progressive decoding, the publisher
/// might emit more than a single value.
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public struct ImagePublisher: Publisher {
    public typealias Output = ImageResponse
    public typealias Failure = ImagePipeline.Error

    public let request: ImageRequest
    public let pipeline: ImagePipeline

    public init(request: ImageRequest, pipeline: ImagePipeline) {
        self.request = request
        self.pipeline = pipeline
    }

    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = ImageSubscription(
            request: self.request,
            pipeline: self.pipeline,
            subscriber: subscriber
        )

        subscriber.receive(subscription: subscription)
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
private final class ImageSubscription<S: Subscriber>: Subscription where S.Input == ImageResponse, S.Failure == ImagePipeline.Error {
    private var task: ImageTask?
    private let subscriber: S?
    private let request: ImageRequest
    private let pipeline: ImagePipeline
    private var isStarted = false

    init(request: ImageRequest, pipeline: ImagePipeline, subscriber: S) {
        self.pipeline = pipeline
        self.request = request
        self.subscriber = subscriber

    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > 0 else { return }
        guard let subscriber = subscriber else { return }

        let request = pipeline.configuration.inheritOptions(self.request)

        if let image = pipeline.cache[request] {
            _ = subscriber.receive(ImageResponse(container: image, cacheType: .memory))

            if !image.isPreview {
                subscriber.receive(completion: .finished)
                return
            }
        }

        task = pipeline.loadImage(
             with: request,
             queue: nil,
             progress: { response, _, _ in
                 if let response = response {
                    // Send progressively decoded image (if enabled and if any)
                     _ = subscriber.receive(response)
                 }
             },
             completion: { result in
                 switch result {
                 case let .success(response):
                    _ = subscriber.receive(response)
                    subscriber.receive(completion: .finished)
                 case let .failure(error):
                     subscriber.receive(completion: .failure(error))
                 }
             }
         )
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
