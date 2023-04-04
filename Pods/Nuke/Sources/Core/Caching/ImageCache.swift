// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

/// An LRU memory cache.
///
/// The elements stored in cache are automatically discarded if either *cost* or
/// *count* limit is reached. The default cost limit represents a number of bytes
/// and is calculated based on the amount of physical memory available on the
/// device. The default count limit is set to `Int.max`.
///
/// `ImageCache` automatically removes all stored elements when it receives a
/// memory warning. It also automatically removes *most* stored elements
/// when the app enters the background.
public final class ImageCache: ImageCaching {
    private let impl: Cache<ImageCacheKey, ImageContainer>

    /// The maximum total cost that the cache can hold.
    public var costLimit: Int {
        get { impl.costLimit }
        set { impl.costLimit = newValue }
    }

    /// The maximum number of items that the cache can hold.
    public var countLimit: Int {
        get { impl.countLimit }
        set { impl.countLimit = newValue }
    }

    /// Default TTL (time to live) for each entry. Can be used to make sure that
    /// the entries get validated at some point. `0` (never expire) by default.
    public var ttl: TimeInterval {
        get { impl.ttl }
        set { impl.ttl = newValue }
    }

    /// The total cost of items in the cache.
    public var totalCost: Int {
        return impl.totalCost
    }

    /// The maximum cost of an entry in proportion to the `costLimit`.
    /// By default, `0.1`.
    public var entryCostLimit: Double = 0.1

    /// The total number of items in the cache.
    public var totalCount: Int {
        return impl.totalCount
    }

    /// Shared `Cache` instance.
    public static let shared = ImageCache()

    deinit {
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageCache")
        #endif
    }

    /// Initializes `Cache`.
    /// - parameter costLimit: Default value representes a number of bytes and is
    /// calculated based on the amount of the phisical memory available on the device.
    /// - parameter countLimit: `Int.max` by default.
    public init(costLimit: Int = ImageCache.defaultCostLimit(), countLimit: Int = Int.max) {
        impl = Cache(costLimit: costLimit, countLimit: countLimit)

        #if TRACK_ALLOCATIONS
        Allocations.increment("ImageCache")
        #endif
    }

    /// Returns a recommended cost limit which is computed based on the amount
    /// of the phisical memory available on the device.
    public static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (536_870_912 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }

    public subscript(key: ImageCacheKey) -> ImageContainer? {
        get {
            return impl.value(forKey: key)
        }
        set {
            if let image = newValue {
                let cost = self.cost(for: image)
                // Take care of overflow or cache size big enough to fit any
                // resonable content (and also of costLimit = Int.max).
                let sanitizedEntryLimit = max(0, min(entryCostLimit, 1))
                if costLimit > 2147483647 || cost < Int(sanitizedEntryLimit * Double(costLimit)) {
                    impl.set(image, forKey: key, cost: cost)
                }
            } else {
                impl.removeValue(forKey: key)
            }
        }
    }

    /// Removes all cached images.
    public func removeAll() {
        impl.removeAll()
    }
    /// Removes least recently used items from the cache until the total cost
    /// of the remaining items is less than the given cost limit.
    public func trim(toCost limit: Int) {
        impl.trim(toCost: limit)
    }

    /// Removes least recently used items from the cache until the total count
    /// of the remaining items is less than the given count limit.
    public func trim(toCount limit: Int) {
        impl.trim(toCount: limit)
    }

    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    func cost(for container: ImageContainer) -> Int {
        let dataCost: Int
        if ImagePipeline.Configuration._isAnimatedImageDataEnabled {
            dataCost = container.image._animatedImageData?.count ?? 0
        } else {
            dataCost = container.data?.count ?? 0
        }

        // bytesPerRow * height gives a rough estimation of how much memory
        // image uses in bytes. In practice this algorithm combined with a
        // conservative default cost limit works OK.
        guard let cgImage = container.image.cgImage else {
            return 1 + dataCost
        }
        return cgImage.bytesPerRow * cgImage.height + dataCost
    }
}

final class Cache<Key: Hashable, Value> {
    // Can't use `NSCache` because it is not LRU

    private var map = [Key: LinkedList<Entry>.Node]()
    private let list = LinkedList<Entry>()
    private let lock = NSLock()
    private let memoryPressure: DispatchSourceMemoryPressure

    var costLimit: Int {
        didSet { lock.sync(_trim) }
    }

    var countLimit: Int {
        didSet { lock.sync(_trim) }
    }

    private(set) var totalCost = 0
    var ttl: TimeInterval = 0

    var totalCount: Int {
        map.count
    }

    init(costLimit: Int, countLimit: Int) {
        self.costLimit = costLimit
        self.countLimit = countLimit
        self.memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        self.memoryPressure.setEventHandler { [weak self] in
            self?.removeAll()
        }
        self.memoryPressure.resume()

        #if os(iOS) || os(tvOS)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(clearCacheOnEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification,
                           object: nil)
        #endif

        #if TRACK_ALLOCATIONS
        Allocations.increment("Cache")
        #endif
    }

    deinit {
        memoryPressure.cancel()

        #if TRACK_ALLOCATIONS
        Allocations.decrement("Cache")
        #endif
    }

    func value(forKey key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }

        guard let node = map[key] else {
            return nil
        }

        guard !node.value.isExpired else {
            _remove(node: node)
            return nil
        }

        // bubble node up to make it last added (most recently used)
        list.remove(node)
        list.append(node)

        return node.value.value
    }

    func set(_ value: Value, forKey key: Key, cost: Int = 0, ttl: TimeInterval? = nil) {
        lock.lock(); defer { lock.unlock() }

        let ttl = ttl ?? self.ttl
        let expiration = ttl == 0 ? nil : (Date() + ttl)
        let entry = Entry(value: value, key: key, cost: cost, expiration: expiration)
        _add(entry)
        _trim() // _trim is extremely fast, it's OK to call it each time
    }

    @discardableResult
    func removeValue(forKey key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }

        guard let node = map[key] else {
            return nil
        }
        _remove(node: node)
        return node.value.value
    }

    private func _add(_ element: Entry) {
        if let existingNode = map[element.key] {
            _remove(node: existingNode)
        }
        map[element.key] = list.append(element)
        totalCost += element.cost
    }

    private func _remove(node: LinkedList<Entry>.Node) {
        list.remove(node)
        map[node.value.key] = nil
        totalCost -= node.value.cost
    }

    @objc
    dynamic func removeAll() {
        lock.sync {
            map.removeAll()
            list.removeAll()
            totalCost = 0
        }
    }

    private func _trim() {
        _trim(toCost: costLimit)
        _trim(toCount: countLimit)
    }

    @objc
    private dynamic func clearCacheOnEnterBackground() {
        // Remove most of the stored items when entering background.
        // This behavior is similar to `NSCache` (which removes all
        // items). This feature is not documented and may be subject
        // to change in future Nuke versions.
        lock.sync {
            _trim(toCost: Int(Double(costLimit) * 0.1))
            _trim(toCount: Int(Double(countLimit) * 0.1))
        }
    }

    func trim(toCost limit: Int) {
        lock.sync { _trim(toCost: limit) }
    }

    private func _trim(toCost limit: Int) {
        _trim(while: { totalCost > limit })
    }

    func trim(toCount limit: Int) {
        lock.sync { _trim(toCount: limit) }
    }

    private func _trim(toCount limit: Int) {
        _trim(while: { totalCount > limit })
    }

    private func _trim(while condition: () -> Bool) {
        while condition(), let node = list.first { // least recently used
            _remove(node: node)
        }
    }

    private struct Entry {
        let value: Value
        let key: Key
        let cost: Int
        let expiration: Date?
        var isExpired: Bool {
            guard let expiration = expiration else {
                return false
            }
            return expiration.timeIntervalSinceNow < 0
        }
    }
}
