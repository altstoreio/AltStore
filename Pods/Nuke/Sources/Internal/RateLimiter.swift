// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Controls the rate at which the work is executed. Uses the classic [token
/// bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm.
///
/// The main use case for rate limiter is to support large (infinite) collections
/// of images by preventing trashing of underlying systems, primary URLSession.
///
/// The implementation supports quick bursts of requests which can be executed
/// without any delays when "the bucket is full". This is important to prevent
/// rate limiter from affecting "normal" requests flow.
final class RateLimiter {
    private let bucket: TokenBucket
    private let queue: DispatchQueue
    private var pending = LinkedList<Work>() // fast append, fast remove first
    private var isExecutingPendingTasks = false

    typealias Work = () -> Bool

    /// Initializes the `RateLimiter` with the given configuration.
    /// - parameter queue: Queue on which to execute pending tasks.
    /// - parameter rate: Maximum number of requests per second. 80 by default.
    /// - parameter burst: Maximum number of requests which can be executed without
    /// any delays when "bucket is full". 25 by default.
    init(queue: DispatchQueue, rate: Int = 80, burst: Int = 25) {
        self.queue = queue
        self.bucket = TokenBucket(rate: Double(rate), burst: Double(burst))

        #if TRACK_ALLOCATIONS
        Allocations.increment("RateLimiter")
        #endif
    }

    deinit {
        #if TRACK_ALLOCATIONS
        Allocations.decrement("RateLimiter")
        #endif
    }

    /// - parameter closure: Returns `true` if the close was executed, `false`
    /// if the work was cancelled.
    func execute( _ work: @escaping Work) {
        if !pending.isEmpty || !bucket.execute(work) {
            pending.append(work)
            setNeedsExecutePendingTasks()
        }
    }

    private func setNeedsExecutePendingTasks() {
        guard !isExecutingPendingTasks else {
            return
        }
        isExecutingPendingTasks = true
        // Compute a delay such that by the time the closure is executed the
        // bucket is refilled to a point that is able to execute at least one
        // pending task. With a rate of 80 tasks we expect a refill every ~26 ms
        // or as soon as the new tasks are added.
        let bucketRate = 1000.0 / bucket.rate
        let delay = Int(2.1 * bucketRate) // 14 ms for rate 80 (default)
        let bounds = min(100, max(15, delay))
        queue.asyncAfter(deadline: .now() + .milliseconds(bounds), execute: executePendingTasks)
    }

    private func executePendingTasks() {
        while let node = pending.first, bucket.execute(node.value) {
            pending.remove(node)
        }
        isExecutingPendingTasks = false
        if !pending.isEmpty { // Not all pending items were executed
            setNeedsExecutePendingTasks()
        }
    }
}

private final class TokenBucket {
    let rate: Double
    private let burst: Double // maximum bucket size
    private var bucket: Double
    private var timestamp: TimeInterval // last refill timestamp

    /// - parameter rate: Rate (tokens/second) at which bucket is refilled.
    /// - parameter burst: Bucket size (maximum number of tokens).
    init(rate: Double, burst: Double) {
        self.rate = rate
        self.burst = burst
        self.bucket = burst
        self.timestamp = CFAbsoluteTimeGetCurrent()
    }

    /// Returns `true` if the closure was executed, `false` if dropped.
    func execute(_ work: () -> Bool) -> Bool {
        refill()
        guard bucket >= 1.0 else {
            return false // bucket is empty
        }
        if work() {
            bucket -= 1.0 // work was cancelled, no need to reduce the bucket
        }
        return true
    }

    private func refill() {
        let now = CFAbsoluteTimeGetCurrent()
        bucket += rate * max(0, now - timestamp) // rate * (time delta)
        timestamp = now
        if bucket > burst { // prevent bucket overflow
            bucket = burst
        }
    }
}
