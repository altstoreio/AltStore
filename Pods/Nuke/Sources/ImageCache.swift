// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation
#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

/// In-memory image cache.
///
/// The implementation must be thread safe.
public protocol ImageCaching: class {
    /// Returns the `ImageResponse` stored in the cache with the given request.
    func cachedResponse(for request: ImageRequest) -> ImageResponse?

    /// Stores the given `ImageResponse` in the cache using the given request.
    func storeResponse(_ response: ImageResponse, for request: ImageRequest)

    /// Remove the response for the given request.
    func removeResponse(for request: ImageRequest)
}

/// Convenience subscript.
public extension ImageCaching {
    /// Accesses the image associated with the given request.
    subscript(request: ImageRequest) -> Image? {
        get {
            return cachedResponse(for: request)?.image
        }
        set {
            if let newValue = newValue {
                storeResponse(ImageResponse(image: newValue, urlResponse: nil), for: request)
            } else {
                removeResponse(for: request)
            }
        }
    }
}

/// Memory cache with LRU cleanup policy (least recently used are removed first).
///
/// The elements stored in cache are automatically discarded if either *cost* or
/// *count* limit is reached. The default cost limit represents a number of bytes
/// and is calculated based on the amount of physical memory available on the
/// device. The default cmount limit is set to `Int.max`.
///
/// `Cache` automatically removes all stored elements when it received a
/// memory warning. It also automatically removes *most* of cached elements
/// when the app enters background.
public final class ImageCache: ImageCaching {
    private let _impl: _Cache<ImageRequest.CacheKey, ImageResponse>

    /// The maximum total cost that the cache can hold.
    public var costLimit: Int {
        get { return _impl.costLimit }
        set { _impl.costLimit = newValue }
    }

    /// The maximum number of items that the cache can hold.
    public var countLimit: Int {
        get { return _impl.countLimit }
        set { _impl.countLimit = newValue }
    }

    /// Default TTL (time to live) for each entry. Can be used to make sure that
    /// the entries get validated at some point. `0` (never expire) by default.
    public var ttl: TimeInterval {
        get { return _impl.ttl }
        set { _impl.ttl = newValue }
    }

    /// The total cost of items in the cache.
    public var totalCost: Int {
        return _impl.totalCost
    }

    /// The total number of items in the cache.
    public var totalCount: Int {
        return _impl.totalCount
    }

    /// Shared `Cache` instance.
    public static let shared = ImageCache()

    /// Initializes `Cache`.
    /// - parameter costLimit: Default value representes a number of bytes and is
    /// calculated based on the amount of the phisical memory available on the device.
    /// - parameter countLimit: `Int.max` by default.
    public init(costLimit: Int = ImageCache.defaultCostLimit(), countLimit: Int = Int.max) {
        _impl = _Cache(costLimit: costLimit, countLimit: countLimit)
    }

    /// Returns a recommended cost limit which is computed based on the amount
    /// of the phisical memory available on the device.
    public static func defaultCostLimit() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let ratio = physicalMemory <= (536_870_912 /* 512 Mb */) ? 0.1 : 0.2
        let limit = physicalMemory / UInt64(1 / ratio)
        return limit > UInt64(Int.max) ? Int.max : Int(limit)
    }

    /// Returns the `ImageResponse` stored in the cache with the given request.
    public func cachedResponse(for request: ImageRequest) -> ImageResponse? {
        return _impl.value(forKey: ImageRequest.CacheKey(request: request))
    }

    /// Stores the given `ImageResponse` in the cache using the given request.
    public func storeResponse(_ response: ImageResponse, for request: ImageRequest) {
        _impl.set(response, forKey: ImageRequest.CacheKey(request: request), cost: self.cost(for: response.image))
    }

    /// Removes response stored with the given request.
    public func removeResponse(for request: ImageRequest) {
        _impl.removeValue(forKey: ImageRequest.CacheKey(request: request))
    }

    /// Removes all cached images.
    public func removeAll() {
        _impl.removeAll()
    }
    /// Removes least recently used items from the cache until the total cost
    /// of the remaining items is less than the given cost limit.
    public func trim(toCost limit: Int) {
        _impl.trim(toCost: limit)
    }

    /// Removes least recently used items from the cache until the total count
    /// of the remaining items is less than the given count limit.
    public func trim(toCount limit: Int) {
        _impl.trim(toCount: limit)
    }

    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    func cost(for image: Image) -> Int {
        #if !os(macOS)
        let dataCost = ImagePipeline.Configuration.isAnimatedImageDataEnabled ? (image.animatedImageData?.count ?? 0) : 0

        // bytesPerRow * height gives a rough estimation of how much memory
        // image uses in bytes. In practice this algorithm combined with a
        // concervative default cost limit works OK.
        guard let cgImage = image.cgImage else {
            return 1 + dataCost
        }
        return cgImage.bytesPerRow * cgImage.height + dataCost

        #else
        return 1
        #endif
    }
}

internal final class _Cache<Key: Hashable, Value> {
    // We don't use `NSCache` because it's not LRU

    private var map = [Key: LinkedList<Entry>.Node]()
    private let list = LinkedList<Entry>()
    private let lock = NSLock()

    var costLimit: Int {
        didSet { lock.sync(_trim) }
    }

    var countLimit: Int {
        didSet { lock.sync(_trim) }
    }

    private(set) var totalCost = 0
    var ttl: TimeInterval = 0

    var totalCount: Int {
        return map.count
    }

    init(costLimit: Int, countLimit: Int) {
        self.costLimit = costLimit
        self.countLimit = countLimit
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(removeAll), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        #endif
    }

    deinit {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self)
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

        guard let node = map[key] else { return nil }
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

    @objc dynamic func removeAll() {
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

    @objc private dynamic func didEnterBackground() {
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
            guard let expiration = expiration else { return false }
            return expiration.timeIntervalSinceNow < 0
        }
    }
}
