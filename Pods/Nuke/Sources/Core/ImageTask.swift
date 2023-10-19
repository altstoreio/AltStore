// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A task performed by the `ImagePipeline`.
///
/// The pipeline maintains a strong reference to the task until the request
/// finishes or fails; you do not need to maintain a reference to the task unless
/// it is useful for your app.
public final class ImageTask: Hashable, CustomStringConvertible {
    /// An identifier that uniquely identifies the task within a given pipeline.
    /// Unique only within that pipeline.
    public let taskId: Int64

    /// The original request.
    public let request: ImageRequest

    let isDataTask: Bool

    /// Updates the priority of the task, even if it is already running.
    public var priority: ImageRequest.Priority {
        didSet {
            pipeline?.imageTaskUpdatePriorityCalled(self, priority: priority)
        }
    }
    var _priority: ImageRequest.Priority // Backing store for access from pipeline
    // Putting all smaller units closer together (1 byte / 1 byte / 1 byte)

    weak var pipeline: ImagePipeline?

    // MARK: Progress

    /// The number of bytes that the task has received.
    public private(set) var completedUnitCount: Int64 = 0

    /// A best-guess upper bound on the number of bytes of the resource.
    public private(set) var totalUnitCount: Int64 = 0

    /// Returns a progress object for the task, created lazily.
    public var progress: Progress {
        if _progress == nil { _progress = Progress() }
        return _progress!
    }
    private var _progress: Progress?

    var isCancelled: Bool { _isCancelled.pointee == 1 }
    private let _isCancelled: UnsafeMutablePointer<Int32>

    var onCancel: (() -> Void)?
    
    deinit {
        self._isCancelled.deallocate()
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageTask")
        #endif
    }

    init(taskId: Int64, request: ImageRequest, isDataTask: Bool) {
        self.taskId = taskId
        self.request = request
        self._priority = request.priority
        self.priority = request.priority
        self.isDataTask = isDataTask

        self._isCancelled = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self._isCancelled.initialize(to: 0)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImageTask")
        #endif
    }

    /// Marks task as being cancelled.
    ///
    /// The pipeline will immediately cancel any work associated with a task
    /// unless there is an equivalent outstanding task running (see
    /// `ImagePipeline.Configuration.isCoalescingEnabled` for more info).
    public func cancel() {
        if OSAtomicCompareAndSwap32Barrier(0, 1, _isCancelled) {
            pipeline?.imageTaskCancelCalled(self)
        }
    }

    func setProgress(_ progress: TaskProgress) {
        completedUnitCount = progress.completed
        totalUnitCount = progress.total
        _progress?.completedUnitCount = progress.completed
        _progress?.totalUnitCount = progress.total
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self).hashValue)
    }

    public static func == (lhs: ImageTask, rhs: ImageTask) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "ImageTask(id: \(taskId), priority: \(priority), completedUnitCount: \(completedUnitCount), totalUnitCount: \(totalUnitCount), isCancelled: \(isCancelled))"
    }
}
