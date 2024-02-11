// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Prefetches and caches images to eliminate delays when requesting the same
/// images later.
///
/// The prefetcher cancels all of the outstanding tasks when deallocated.
///
/// All `ImagePrefetcher` methods are thread-safe and are optimized to be used
/// even from the main thread during scrolling.
public final class ImagePrefetcher {
    private let pipeline: ImagePipeline
    private var tasks = [ImageLoadKey: Task]()
    private let destination: Destination
    let queue = OperationQueue() // internal for testing
    public var didComplete: (() -> Void)? // called when # of in-flight tasks decrements to 0

    /// Pauses the prefetching.
    ///
    /// - note: When you pause, the prefetcher will finish outstanding tasks
    /// (by default, there are only 2 at a time), and pause the rest.
    public var isPaused: Bool = false {
        didSet { queue.isSuspended = isPaused }
    }

    /// The priority of the requests. By default, `.low`.
    ///
    /// Changing the priority also changes the priority of all of the outstanding
    /// tasks managed by the prefetcher.
    public var priority: ImageRequest.Priority = .low {
        didSet {
            let newValue = priority
            pipeline.queue.async { self.didUpdatePriority(to: newValue) }
        }
    }
    private var _priority: ImageRequest.Priority = .low

    /// Prefetching destination.
    public enum Destination {
        /// Prefetches the image and stores it in both the memory and the disk
        /// cache (make sure to enable it).
        case memoryCache

        /// Prefetches the image data and stores it in disk caches. It does not
        /// require decoding the image data and therefore requires less CPU.
        ///
        /// - warning: This option is incompatible with `DataCachePolicy.automatic`
        /// (for requests with processors) and `DataCachePolicy.storeEncodedImages`.
        case diskCache
    }

    /// Initializes the `ImagePrefetcher` instance.
    /// - parameter manager: `Loader.shared` by default.
    /// - parameter destination: `.memoryCache` by default.
    /// - parameter `maxConcurrentRequestCount`: 2 by default.
    public init(pipeline: ImagePipeline = ImagePipeline.shared,
                destination: Destination = .memoryCache,
                maxConcurrentRequestCount: Int = 2) {
        self.pipeline = pipeline
        self.destination = destination
        self.queue.maxConcurrentOperationCount = maxConcurrentRequestCount
        self.queue.underlyingQueue = pipeline.queue

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImagePrefetcher")
        #endif
    }

    deinit {
        let tasks = self.tasks.values // Make sure we don't retain self
        pipeline.queue.async {
            for task in tasks {
                task.cancel()
            }
        }

        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImagePrefetcher")
        #endif
    }

    /// Starts prefetching images for the given requests.
    ///
    /// When you need to display the same image later, use the `ImagePipeline`
    /// or the view extensions to load it as usual. The pipeline will take care
    /// of coalescing the requests to avoid any duplicate work.
    ///
    /// The priority of the requests is set to the priority of the prefetcher
    /// (`.low` by default).
    public func startPrefetching(with requests: [ImageRequestConvertible]) {
        pipeline.queue.async {
            for request in requests {
                var request = request.asImageRequest()
                request.priority = self._priority
                self._startPrefetching(with: request)
            }
        }
    }

    private func _startPrefetching(with request: ImageRequest) {
        guard pipeline.cache[request] == nil else {
            return // The image is already in memory cache
        }

        let key = request.makeImageLoadKey()
        guard tasks[key] == nil else {
            return // Already started prefetching
        }

        let task = Task(request: request, key: key)
        task.operation = queue.add { [weak self] finish in
            guard let self = self else { return finish() }
            self.loadImage(task: task, finish: finish)
        }
        tasks[key] = task
    }

    private func loadImage(task: Task, finish: @escaping () -> Void) {
        switch destination {
        case .diskCache:
            task.imageTask = pipeline.loadData(with: task.request, isConfined: true, queue: pipeline.queue, progress: nil) { [weak self] _ in
                self?._remove(task)
                finish()
            }
        case .memoryCache:
            task.imageTask = pipeline.loadImage(with: task.request, isConfined: true, queue: pipeline.queue, progress: nil) { [weak self] _ in
                self?._remove(task)
                finish()
            }
        }
        task.onCancelled = finish
    }

    private func _remove(_ task: Task) {
        guard tasks[task.key] === task else { return } // Should never happen
        tasks[task.key] = nil
        if tasks.isEmpty {
            didComplete?()
        }
    }

    /// Stops prefetching images for the given requests and cancels outstanding
    /// requests.
    ///
    /// You don't need to balance the number of `start` and `stop` requests.
    /// If you have multiple screens with prefetching, create multiple instances
    /// of `ImagePrefetcher`.
    ///
    /// - parameter destination: `.memoryCache` by default.
    public func stopPrefetching(with requests: [ImageRequestConvertible]) {
        pipeline.queue.async {
            for request in requests {
                self._stopPrefetching(with: request.asImageRequest())
            }
        }
    }

    private func _stopPrefetching(with request: ImageRequest) {
        if let task = tasks.removeValue(forKey: request.makeImageLoadKey()) {
            task.cancel()
        }
    }

    /// Stops all prefetching tasks.
    public func stopPrefetching() {
        pipeline.queue.async {
            self.tasks.values.forEach { $0.cancel() }
            self.tasks.removeAll()
        }
    }

    private func didUpdatePriority(to priority: ImageRequest.Priority) {
        guard _priority != priority else { return }
        _priority = priority
        for task in tasks.values {
            task.imageTask?.priority = priority
        }
    }

    private final class Task {
        let key: ImageLoadKey
        let request: ImageRequest
        weak var imageTask: ImageTask?
        weak var operation: Operation?
        var onCancelled: (() -> Void)?

        init(request: ImageRequest, key: ImageLoadKey) {
            self.request = request
            self.key = key
        }

        // When task is cancelled, it is removed from the prefetcher and can
        // never get cancelled twice.
        func cancel() {
            operation?.cancel()
            imageTask?.cancel()
            onCancelled?()
        }
    }
}
