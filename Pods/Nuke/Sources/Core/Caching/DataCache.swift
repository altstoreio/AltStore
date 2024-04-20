// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An LRU disk cache that stores data in separate files.
///
/// The DataCache uses LRU cleanup policy (least recently used items are removed
/// first). The elements stored in the cache are automatically discarded if
/// either *cost* or *count* limit is reached. The sweeps are performed periodically.
///
/// DataCache always writes and removes data asynchronously. It also allows for
/// reading and writing data in parallel. This is implemented using a "staging"
/// area which stores changes until they are flushed to disk:
///
///     // Schedules data to be written asynchronously and returns immediately
///     cache[key] = data
///
///     // The data is returned from the staging area
///     let data = cache[key]
///
///     // Schedules data to be removed asynchronously and returns immediately
///     cache[key] = nil
///
///     // Data is nil
///     let data = cache[key]
///
/// Thread-safe.
///
/// - warning: It's possible to have more than one instance of `DataCache` with
/// the same `path` but it is not recommended.
public final class DataCache: DataCaching {
    /// A cache key.
    public typealias Key = String

    /// Size limit in bytes. `150 Mb` by default.
    ///
    /// Changes to `sizeLimit` will take effect when the next LRU sweep is run.
    public var sizeLimit: Int = 1024 * 1024 * 150

    /// When performing a sweep, the cache will remote entries until the size of
    /// the remaining items is lower than or equal to `sizeLimit * trimRatio` and
    /// the total count is lower than or equal to `countLimit * trimRatio`. `0.7`
    /// by default.
    var trimRatio = 0.7

    /// The path for the directory managed by the cache.
    public let path: URL

    /// The number of seconds between each LRU sweep. 30 by default.
    /// The first sweep is performed right after the cache is initialized.
    ///
    /// Sweeps are performed in a background and can be performed in parallel
    /// with reading.
    public var sweepInterval: TimeInterval = 30

    /// The delay after which the initial sweep is performed. 10 by default.
    /// The initial sweep is performed after a delay to avoid competing with
    /// other subsystems for the resources.
    private var initialSweepDelay: TimeInterval = 10

    // Staging

    private let lock = NSLock()
    private var staging = Staging()
    private var isFlushNeeded = false
    private var isFlushScheduled = false
    var flushInterval: DispatchTimeInterval = .seconds(1)

    /// A queue which is used for disk I/O.
    public let queue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.WriteQueue", qos: .utility)

    /// A function which generates a filename for the given key. A good candidate
    /// for a filename generator is a _cryptographic_ hash function like SHA1.
    ///
    /// The reason why filename needs to be generated in the first place is
    /// that filesystems have a size limit for filenames (e.g. 255 UTF-8 characters
    /// in AFPS) and do not allow certain characters to be used in filenames.
    public typealias FilenameGenerator = (_ key: String) -> String?

    private let filenameGenerator: FilenameGenerator

    /// Creates a cache instance with a given `name`. The cache creates a directory
    /// with the given `name` in a `.cachesDirectory` in `.userDomainMask`.
    /// - parameter filenameGenerator: Generates a filename for the given URL.
    /// The default implementation generates a filename using SHA1 hash function.
    public convenience init(name: String, filenameGenerator: @escaping (String) -> String? = DataCache.filename(for:)) throws {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        }
        try self.init(path: root.appendingPathComponent(name, isDirectory: true), filenameGenerator: filenameGenerator)
    }

    /// Creates a cache instance with a given path.
    /// - parameter filenameGenerator: Generates a filename for the given URL.
    /// The default implementation generates a filename using SHA1 hash function.
    public init(path: URL, filenameGenerator: @escaping (String) -> String? = DataCache.filename(for:)) throws {
        self.path = path
        self.filenameGenerator = filenameGenerator
        try self.didInit()

        #if TRACK_ALLOCATIONS
        Allocations.increment("DataCache")
        #endif
    }

    deinit {
        #if TRACK_ALLOCATIONS
        Allocations.decrement("ImageCache")
        #endif
    }

    /// A `FilenameGenerator` implementation which uses SHA1 hash function to
    /// generate a filename from the given key.
    public static func filename(for key: String) -> String? {
        key.sha1
    }

    private func didInit() throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
        queue.asyncAfter(deadline: .now() + initialSweepDelay) { [weak self] in
            self?.performAndScheduleSweep()
        }
    }

    // MARK: DataCaching

    /// Retrieves data for the given key.
    public func cachedData(for key: Key) -> Data? {
        if let change = change(for: key) {
            switch change { // Change wasn't flushed to disk yet
            case let .add(data):
                return data
            case .remove:
                return nil
            }
        }
        guard let url = url(for: key) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Returns `true` if the cache contains the data for the given key.
    public func containsData(for key: String) -> Bool {
        if let change = change(for: key) {
            switch change { // Change wasn't flushed to disk yet
            case .add:
                return true
            case .remove:
                return false
            }
        }
        guard let url = url(for: key) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func change(for key: String) -> Staging.ChangeType? {
        lock.lock()
        defer { lock.unlock() }
        return staging.change(for: key)
    }

    /// Stores data for the given key. The method returns instantly and the data
    /// is written asynchronously.
    public func storeData(_ data: Data, for key: Key) {
        stage { staging.add(data: data, for: key) }
    }

    /// Removes data for the given key. The method returns instantly, the data
    /// is removed asynchronously.
    public func removeData(for key: Key) {
        stage { staging.removeData(for: key) }
    }

    /// Removes all items. The method returns instantly, the data is removed
    /// asynchronously.
    public func removeAll() {
        stage { staging.removeAll() }
    }

    private func stage(_ change: () -> Void) {
        lock.lock()
        change()
        setNeedsFlushChanges()
        lock.unlock()
    }

    /// Accesses the data associated with the given key for reading and writing.
    ///
    /// When you assign a new data for a key and the key already exists, the cache
    /// overwrites the existing data.
    ///
    /// When assigning or removing data, the subscript adds a requested operation
    /// in a staging area and returns immediately. The staging area allows for
    /// reading and writing data in parallel.
    ///
    ///     // Schedules data to be written asynchronously and returns immediately
    ///     cache[key] = data
    ///
    ///     // The data is returned from the staging area
    ///     let data = cache[key]
    ///
    ///     // Schedules data to be removed asynchronously and returns immediately
    ///     cache[key] = nil
    ///
    ///     // Data is nil
    ///     let data = cache[key]
    ///
    public subscript(key: Key) -> Data? {
        get {
            cachedData(for: key)
        }
        set {
            if let data = newValue {
                storeData(data, for: key)
            } else {
                removeData(for: key)
            }
        }
    }

    // MARK: Managing URLs

    /// Uses the `FilenameGenerator` that the cache was initialized with to
    /// generate and return a filename for the given key.
    public func filename(for key: Key) -> String? {
        filenameGenerator(key)
    }

    /// Returns `url` for the given cache key.
    public func url(for key: Key) -> URL? {
        guard let filename = self.filename(for: key) else {
            return nil
        }
        return self.path.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: Flush Changes

    /// Synchronously waits on the caller's thread until all outstanding disk I/O
    /// operations are finished.
    public func flush() {
        queue.sync(execute: flushChangesIfNeeded)
    }

    /// Synchronously waits on the caller's thread until all outstanding disk I/O
    /// operations for the given key are finished.
    public func flush(for key: Key) {
        queue.sync {
            guard let change = lock.sync({ staging.changes[key] }) else { return }
            perform(change)
            lock.sync { staging.flushed(change) }
        }
    }

    private func setNeedsFlushChanges() {
        guard !isFlushNeeded else { return }
        isFlushNeeded = true
        scheduleNextFlush()
    }

    private func scheduleNextFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        queue.asyncAfter(deadline: .now() + flushInterval, execute: flushChangesIfNeeded)
    }

    private func flushChangesIfNeeded() {
        // Create a snapshot of the recently made changes
        let staging: Staging
        lock.lock()
        guard isFlushNeeded else {
            return lock.unlock()
        }
        staging = self.staging
        isFlushNeeded = false
        lock.unlock()

        // Apply the snapshot to disk
        performChanges(for: staging)

        // Update the staging area and schedule the next flush if needed
        lock.lock()
        self.staging.flushed(staging)
        isFlushScheduled = false
        if isFlushNeeded {
            scheduleNextFlush()
        }
        lock.unlock()
    }

    // MARK: - I/O

    private func performChanges(for staging: Staging) {
        autoreleasepool {
            if let change = staging.changeRemoveAll {
                perform(change)
            }
            for change in staging.changes.values {
                perform(change)
            }
        }
    }

    private func perform(_ change: Staging.ChangeRemoveAll) {
        try? FileManager.default.removeItem(at: self.path)
        try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
    }

    /// Performs the IO for the given change.
    private func perform(_ change: Staging.Change) {
        guard let url = url(for: change.key) else {
            return
        }
        switch change.type {
        case let .add(data):
            do {
                try data.write(to: url)
            } catch let error as NSError {
                guard error.code == CocoaError.fileNoSuchFile.rawValue && error.domain == CocoaError.errorDomain else { return }
                try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
                try? data.write(to: url) // re-create a directory and try again
            }
        case .remove:
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Sweep

    private func performAndScheduleSweep() {
        performSweep()
        queue.asyncAfter(deadline: .now() + sweepInterval) { [weak self] in
            self?.performAndScheduleSweep()
        }
    }

    /// Synchronously performs a cache sweep and removes the least recently items
    /// which no longer fit in cache.
    public func sweep() {
        queue.sync(execute: performSweep)
    }

    /// Discards the least recently used items first.
    private func performSweep() {
        var items = contents(keys: [.contentAccessDateKey, .totalFileAllocatedSizeKey])
        guard !items.isEmpty else {
            return
        }
        var size = items.reduce(0) { $0 + ($1.meta.totalFileAllocatedSize ?? 0) }

        guard size > sizeLimit else {
            return // All good, no need to perform any work.
        }

        let targetSizeLimit = Int(Double(self.sizeLimit) * trimRatio)

        // Most recently accessed items first
        let past = Date.distantPast
        items.sort { // Sort in place
            ($0.meta.contentAccessDate ?? past) > ($1.meta.contentAccessDate ?? past)
        }

        // Remove the items until it satisfies both size and count limits.
        while size > targetSizeLimit, let item = items.popLast() {
            size -= (item.meta.totalFileAllocatedSize ?? 0)
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    // MARK: Contents

    struct Entry {
        let url: URL
        let meta: URLResourceValues
    }

    func contents(keys: [URLResourceKey] = []) -> [Entry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else {
            return []
        }
        let keys = Set(keys)
        return urls.compactMap {
            guard let meta = try? $0.resourceValues(forKeys: keys) else {
                return nil
            }
            return Entry(url: $0, meta: meta)
        }
    }

    // MARK: Inspection

    /// The total number of items in the cache.
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalCount: Int {
        contents().count
    }

    /// The total file size of items written on disk.
    ///
    /// Uses `URLResourceKey.fileSizeKey` to calculate the size of each entry.
    /// The total allocated size (see `totalAllocatedSize`. on disk might
    /// actually be bigger.
    ///
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalSize: Int {
        contents(keys: [.fileSizeKey]).reduce(0) {
            $0 + ($1.meta.fileSize ?? 0)
        }
    }

    /// The total file allocated size of all the items written on disk.
    ///
    /// Uses `URLResourceKey.totalFileAllocatedSizeKey`.
    ///
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalAllocatedSize: Int {
        contents(keys: [.totalFileAllocatedSizeKey]).reduce(0) {
            $0 + ($1.meta.totalFileAllocatedSize ?? 0)
        }
    }
}

// MARK: - Staging

/// DataCache allows for parallel reads and writes. This is made possible by
/// DataCacheStaging.
///
/// For example, when the data is added in cache, it is first added to staging
/// and is removed from staging only after data is written to disk. Removal works
/// the same way.
private struct Staging {
    private(set) var changes = [String: Change]()
    private(set) var changeRemoveAll: ChangeRemoveAll?

    struct ChangeRemoveAll {
        let id: Int
    }

    struct Change {
        let key: String
        let id: Int
        let type: ChangeType
    }

    enum ChangeType {
        case add(Data)
        case remove
    }

    private var nextChangeId = 0

    // MARK: Changes

    func change(for key: String) -> ChangeType? {
        if let change = changes[key] {
            return change.type
        }
        if changeRemoveAll != nil {
            return .remove
        }
        return nil
    }

    // MARK: Register Changes

    mutating func add(data: Data, for key: String) {
        nextChangeId += 1
        changes[key] = Change(key: key, id: nextChangeId, type: .add(data))
    }

    mutating func removeData(for key: String) {
        nextChangeId += 1
        changes[key] = Change(key: key, id: nextChangeId, type: .remove)
    }

    mutating func removeAll() {
        nextChangeId += 1
        changeRemoveAll = ChangeRemoveAll(id: nextChangeId)
        changes.removeAll()
    }

    // MARK: Flush Changes

    mutating func flushed(_ staging: Staging) {
        for change in staging.changes.values {
            flushed(change)
        }
        if let change = staging.changeRemoveAll {
            flushed(change)
        }
    }

    mutating func flushed(_ change: Change) {
        if let index = changes.index(forKey: change.key),
            changes[index].value.id == change.id {
            changes.remove(at: index)
        }
    }

    mutating func flushed(_ change: ChangeRemoveAll) {
        if changeRemoveAll?.id == change.id {
            changeRemoveAll = nil
        }
    }
}
