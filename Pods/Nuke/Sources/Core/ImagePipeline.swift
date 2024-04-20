// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// `ImagePipeline` is the primary way to load images directly (without a UI).
///
/// The pipeline is fully customizable. You can change its configuration using
/// `ImagePipeline.Configuration` type: set custom data loader and cache, configure
/// image encoders and decoders, etc. You can also set an `ImagePipelineDelegate`
/// to get even more granular control on a per-request basis.
///
/// See ["Image Pipeline"](https://kean.blog/nuke/guides/image-pipeline) to learn
/// more about how to use the pipeline. You can also learn about they way it
/// works internally in a [dedicated guide](https://kean.blog/nuke/guides/image-pipeline-guide).
///
/// `ImagePipeline` also suppors Combine. You can learn more in a dedicated
/// [guide](https://kean.blog/nuke/guides/combine) with some common use-cases.
///
/// `ImagePipeline` is fully thread-safe.
public final class ImagePipeline {
    /// Shared image pipeline.
    public static var shared = ImagePipeline(configuration: .withURLCache)

    /// The pipeline configuration.
    public let configuration: Configuration

    /// Provides access to the underlying caching subsystems.
    public var cache: ImagePipeline.Cache { ImagePipeline.Cache(pipeline: self) }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use ImagePipelineDelegate")
    public var observer: ImagePipelineObserving?

    let delegate: ImagePipelineDelegate // swiftlint:disable:this all
    private(set) var imageCache: ImageCache?

    private var tasks = [ImageTask: TaskSubscription]()

    private let tasksLoadData: TaskPool<ImageLoadKey, (Data, URLResponse?), Error>
    private let tasksLoadImage: TaskPool<ImageLoadKey, ImageResponse, Error>
    private let tasksFetchDecodedImage: TaskPool<DecodedImageLoadKey, ImageResponse, Error>
    private let tasksFetchOriginalImageData: TaskPool<DataLoadKey, (Data, URLResponse?), Error>
    private let tasksProcessImage: TaskPool<ImageProcessingKey, ImageResponse, Swift.Error>

    // The queue on which the entire subsystem is synchronized.
    let queue = DispatchQueue(label: "com.github.kean.Nuke.ImagePipeline", qos: .userInitiated)
    private var isInvalidated = false

    private var nextTaskId: Int64 { OSAtomicIncrement64(_nextTaskId) }
    private let _nextTaskId: UnsafeMutablePointer<Int64>

    let rateLimiter: RateLimiter?
    let id = UUID()

    deinit {
        _nextTaskId.deallocate()

        ResumableDataStorage.shared.unregister(self)
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImagePipeline")
        #endif
    }

    /// Initializes `ImagePipeline` instance with the given configuration.
    ///
    /// - parameter configuration: `Configuration()` by default.
    /// - parameter delegate: `nil` by default.
    public init(configuration: Configuration = Configuration(), delegate: ImagePipelineDelegate? = nil) {
        self.configuration = configuration
        self.rateLimiter = configuration.isRateLimiterEnabled ? RateLimiter(queue: queue) : nil
        self.delegate = delegate ?? ImagePipelineDefaultDelegate()

        let isCoalescingEnabled = configuration.isTaskCoalescingEnabled
        self.tasksLoadData = TaskPool(isCoalescingEnabled)
        self.tasksLoadImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchDecodedImage = TaskPool(isCoalescingEnabled)
        self.tasksFetchOriginalImageData = TaskPool(isCoalescingEnabled)
        self.tasksProcessImage = TaskPool(isCoalescingEnabled)

        self._nextTaskId = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self._nextTaskId.initialize(to: 0)

        if let imageCache = configuration.imageCache as? ImageCache {
            self.imageCache = imageCache
        }

        ResumableDataStorage.shared.register(self)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImagePipeline")
        #endif
    }

    public convenience init(delegate: ImagePipelineDelegate? = nil, _ configure: (inout ImagePipeline.Configuration) -> Void) {
        var configuration = ImagePipeline.Configuration()
        configure(&configuration)
        self.init(configuration: configuration, delegate: delegate)
    }

    /// Invalidates the pipeline and cancels all outstanding tasks. No new
    /// requests can be started.
    public func invalidate() {
        queue.async {
            guard !self.isInvalidated else { return }
            self.isInvalidated = true
            self.tasks.keys.forEach(self.cancel)
        }
    }

    // MARK: - Loading Images

    /// Loads an image for the given request.
    @discardableResult public func loadImage(
        with request: ImageRequestConvertible,
        completion: @escaping (_ result: Result<ImageResponse, Error>) -> Void
    ) -> ImageTask {
        loadImage(with: request, queue: nil, progress: nil, completion: completion)
    }

    /// Loads an image for the given request.
    ///
    /// See [Nuke Docs](https://kean.blog/nuke/guides/image-pipeline) to learn more.
    ///
    /// - parameter request: An image request.
    /// - parameter queue: A queue on which to execute `progress` and `completion`
    /// callbacks. By default, the pipeline uses `.main` queue.
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished. `nil` by default.
    @discardableResult public func loadImage(
        with request: ImageRequestConvertible,
        queue: DispatchQueue? = nil,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping ((_ result: Result<ImageResponse, Error>) -> Void)
    ) -> ImageTask {
        loadImage(with: request.asImageRequest(), isConfined: false, queue: queue, progress: progress, completion: completion)
    }

    func loadImage(
        with request: ImageRequest,
        isConfined: Bool,
        queue: DispatchQueue?,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?,
        onCancel: (() -> Void)? = nil,
        completion: ((_ result: Result<ImageResponse, Error>) -> Void)?
    ) -> ImageTask {
        let request = configuration.inheritOptions(request)
        let task = ImageTask(taskId: nextTaskId, request: request, isDataTask: false)
        task.pipeline = self
        if let onCancel = onCancel {
            task.onCancel = { [weak self] in self?.dispatchCallback(to: queue, onCancel) }
        }
        if isConfined {
            self.startImageTask(task, callbackQueue: queue, progress: progress, completion: completion)
        } else {
            self.queue.async {
                self.startImageTask(task, callbackQueue: queue, progress: progress, completion: completion)
            }
        }
        return task
    }

    private func startImageTask(
        _ task: ImageTask,
        callbackQueue: DispatchQueue?,
        progress progressHandler: ((ImageResponse?, Int64, Int64) -> Void)?,
        completion: ((_ result: Result<ImageResponse, Error>) -> Void)?
    ) {
        guard !isInvalidated else { return }

        self.send(.started, task)

        tasks[task] = makeTaskLoadImage(for: task.request)
            .subscribe(priority: task._priority.taskPriority, subscriber: task) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                self.send(ImageTaskEvent(event), task)

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                self.dispatchCallback(to: callbackQueue) {
                    guard !task.isCancelled else { return }

                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            completion?(.success(response))
                        } else {
                            progressHandler?(response, task.completedUnitCount, task.totalUnitCount)
                        }
                    case let .progress(progress):
                        task.setProgress(progress)
                        progressHandler?(nil, progress.completed, progress.total)
                    case let .error(error):
                        completion?(.failure(error))
                    }
                }
        }
    }

    // MARK: - Loading Image Data

    /// Loads the image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    @discardableResult public func loadData(
        with request: ImageRequestConvertible,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request, queue: nil, progress: nil, completion: completion)
    }

    /// Loads the image data for the given request. The data doesn't get decoded
    /// or processed in any other way.
    ///
    /// You can call `loadImage(:)` for the request at any point after calling
    /// `loadData(:)`, the pipeline will use the same operation to load the data,
    /// no duplicated work will be performed.
    ///
    /// - parameter request: An image request.
    /// - parameter queue: A queue on which to execute `progress` and `completion`
    /// callbacks. By default, the pipeline uses `.main` queue.
    /// - parameter progress: A closure to be called periodically on the main thread
    /// when the progress is updated. `nil` by default.
    /// - parameter completion: A closure to be called on the main thread when the
    /// request is finished.
    @discardableResult public func loadData(
        with request: ImageRequestConvertible,
        queue: DispatchQueue? = nil,
        progress: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        loadData(with: request.asImageRequest(), isConfined: false, queue: queue, progress: progress, completion: completion)
    }

    func loadData(
        with request: ImageRequest,
        isConfined: Bool,
        queue callbackQueue: DispatchQueue?,
        progress: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) -> ImageTask {
        let task = ImageTask(taskId: nextTaskId, request: request, isDataTask: true)
        task.pipeline = self
        if isConfined {
            self.startDataTask(task, callbackQueue: callbackQueue, progress: progress, completion: completion)
        } else {
            self.queue.async {
                self.startDataTask(task, callbackQueue: callbackQueue, progress: progress, completion: completion)
            }
        }
        return task
    }

    private func startDataTask(
        _ task: ImageTask,
        callbackQueue: DispatchQueue?,
        progress progressHandler: ((_ completed: Int64, _ total: Int64) -> Void)?,
        completion: @escaping (Result<(data: Data, response: URLResponse?), Error>) -> Void
    ) {
        guard !isInvalidated else { return }

        tasks[task] = makeTaskLoadData(for: task.request)
            .subscribe(priority: task._priority.taskPriority, subscriber: task) { [weak self, weak task] event in
                guard let self = self, let task = task else { return }

                if event.isCompleted {
                    self.tasks[task] = nil
                }

                self.dispatchCallback(to: callbackQueue) {
                    guard !task.isCancelled else { return }

                    switch event {
                    case let .value(response, isCompleted):
                        if isCompleted {
                            completion(.success(response))
                        }
                    case let .progress(progress):
                        task.setProgress(progress)
                        progressHandler?(progress.completed, progress.total)
                    case let .error(error):
                        completion(.failure(error))
                    }
                }
            }
    }

    // MARK: - Errors

    /// Represents all possible image pipeline errors.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// Data loader failed to load image data with a wrapped error.
        case dataLoadingFailed(Swift.Error)
        /// Decoder failed to produce a final image.
        case decodingFailed
        /// Processor failed to produce a final image.
        case processingFailed(ImageProcessing)

        public var description: String {
            switch self {
            case let .dataLoadingFailed(error): return "Failed to load image data: \(error)"
            case .decodingFailed: return "Failed to create an image from the image data"
            case .processingFailed(let processor): return "Failed to process the image using processor \(processor)"
            }
        }

        /// Returns underlying data loading error.
        public var dataLoadingError: Swift.Error? {
            switch self {
            case .dataLoadingFailed(let error):
                return error
            default:
                return nil
            }
        }
    }

    // MARK: - Image Task Events

    func imageTaskCancelCalled(_ task: ImageTask) {
        queue.async {
            self.cancel(task)
        }
    }

    private func cancel(_ task: ImageTask) {
        guard let subscription = self.tasks.removeValue(forKey: task) else { return }
        if !task.isDataTask {
            self.send(.cancelled, task)
        }
        task.onCancel?()
        subscription.unsubscribe()
    }

    func imageTaskUpdatePriorityCalled(_ task: ImageTask, priority: ImageRequest.Priority) {
        queue.async {
            task._priority = priority
            guard let subscription = self.tasks[task] else { return }
            if !task.isDataTask {
                self.send(.priorityUpdated(priority: priority), task)
            }
            subscription.setPriority(priority.taskPriority)
        }
    }

    private func dispatchCallback(to callbackQueue: DispatchQueue?, _ closure: @escaping () -> Void) {
        if callbackQueue === self.queue {
            closure()
        } else {
            (callbackQueue ?? self.configuration.callbackQueue).async(execute: closure)
        }
    }

    // MARK: - Task Factory (Private)

    // When you request an image or image data, the pipeline creates a graph of tasks
    // (some tasks are added to the graph on demand).
    //
    // `loadImage()` call is represented by TaskLoadImage:
    //
    // TaskLoadImage -> TaskFetchDecodedImage -> TaskFetchOriginalImageData
    //               -> TaskProcessImage
    //
    // `loadData()` call is represented by TaskLoadData:
    //
    // TaskLoadData -> TaskFetchOriginalImageData
    //
    //
    // Each task represents a resource or a piece of work required to produce the
    // final result. The pipeline reduces the amount of duplicated work by coalescing
    // the tasks that represent the same work. For example, if you all `loadImage()`
    // and `loadData()` with the same request, only on `TaskFetchOriginalImageData`
    // is created. The work is split between tasks to minimize any duplicated work.

    func makeTaskLoadImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksLoadImage.publisherForKey(request.makeImageLoadKey()) {
            TaskLoadImage(self, request)
        }
    }

    func makeTaskLoadData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), Error>.Publisher {
        tasksLoadData.publisherForKey(request.makeImageLoadKey()) {
            TaskLoadData(self, request)
        }
    }

    func makeTaskProcessImage(key: ImageProcessingKey, process: @escaping () -> ImageResponse?) -> AsyncTask<ImageResponse, Swift.Error>.Publisher {
        tasksProcessImage.publisherForKey(key) {
            OperationTask(self, configuration.imageProcessingQueue, process)
        }
    }

    func makeTaskFetchDecodedImage(for request: ImageRequest) -> AsyncTask<ImageResponse, Error>.Publisher {
        tasksFetchDecodedImage.publisherForKey(request.makeDecodedImageLoadKey()) {
            TaskFetchDecodedImage(self, request)
        }
    }

    func makeTaskFetchOriginalImageData(for request: ImageRequest) -> AsyncTask<(Data, URLResponse?), Error>.Publisher {
        tasksFetchOriginalImageData.publisherForKey(request.makeDataLoadKey()) {
            request.publisher == nil ?
                TaskFetchOriginalImageData(self, request) :
                TaskFetchWithPublisher(self, request)
        }
    }
}

// MARK: - Misc (Private)

extension ImagePipeline: SendEventProtocol {
    func send(_ event: ImageTaskEvent, _ task: ImageTask) {
        delegate.pipeline(self, imageTask: task, didReceiveEvent: event)
        (self as SendEventProtocol)._send(event, task)
    }

    // Deprecated in 10.0.0
    @available(*, deprecated, message: "Please use ImagePipelineDelegate")
    func _send(_ event: ImageTaskEvent, _ task: ImageTask) {
        observer?.pipeline(self, imageTask: task, didReceiveEvent: event)
    }
}

// Just to workaround the deprecation warning.
private protocol SendEventProtocol {
    func _send(_ event: ImageTaskEvent, _ task: ImageTask)
}
