// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// MARK: - DataCaching

/// Data cache.
///
/// - warning: The implementation must be thread safe.
public protocol DataCaching {
    /// Retrieves data from cache for the given key.
    func cachedData(for key: String) -> Data?

    /// Stores data for the given key.
    /// - note: The implementation must return immediately and store data
    /// asynchronously.
    func storeData(_ data: Data, for key: String)
}

// MARK: - DataCache

/// Data cache backed by a local storage.
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

    /// The maximum number of items. `1000` by default.
    ///
    /// Changes tos `countLimit` will take effect when the next LRU sweep is run.
    public var countLimit: Int = 1000

    /// Size limit in bytes. `100 Mb` by default.
    ///
    /// Changes to `sizeLimit` will take effect when the next LRU sweep is run.
    public var sizeLimit: Int = 1024 * 1024 * 100

    /// When performing a sweep, the cache will remote entries until the size of
    /// the remaining items is lower than or equal to `sizeLimit * trimRatio` and
    /// the total count is lower than or equal to `countLimit * trimRatio`. `0.7`
    /// by default.
    internal var trimRatio = 0.7

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
    private var initialSweepDelay: TimeInterval = 15

    // Staging
    private let _lock = NSLock()
    private var _staging = Staging()

    /* testable */ let _wqueue = DispatchQueue(label: "com.github.kean.Nuke.DataCache.WriteQueue")

    /// A function which generates a filename for the given key. A good candidate
    /// for a filename generator is a _cryptographic_ hash function like SHA1.
    ///
    /// The reason why filename needs to be generated in the first place is
    /// that filesystems have a size limit for filenames (e.g. 255 UTF-8 characters
    /// in AFPS) and do not allow certain characters to be used in filenames.
    public typealias FilenameGenerator = (_ key: String) -> String?

    private let _filenameGenerator: FilenameGenerator

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
        self._filenameGenerator = filenameGenerator
        try self._didInit()
    }

    /// A `FilenameGenerator` implementation which uses SHA1 hash function to
    /// generate a filename from the given key.
    public static func filename(for key: String) -> String? {
        return key.sha1
    }

    private func _didInit() throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
        _wqueue.asyncAfter(deadline: .now() + initialSweepDelay) { [weak self] in
            self?._performAndScheduleSweep()
        }
    }

    // MARK: DataCaching

    /// Retrieves data for the given key. The completion will be called
    /// syncrhonously if there is no cached data for the given key.
    public func cachedData(for key: Key) -> Data? {
        _lock.lock()

        if let change = _staging.change(for: key) {
            _lock.unlock()
            switch change {
            case let .add(data):
                return data
            case .remove:
                return nil
            }
        }

        _lock.unlock()

        guard let url = _url(for: key) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Stores data for the given key. The method returns instantly and the data
    /// is written asynchronously.
    public func storeData(_ data: Data, for key: Key) {
        _lock.sync {
            let change = _staging.add(data: data, for: key)
            _wqueue.async {
                if let url = self._url(for: key) {
                    try? data.write(to: url)
                }
                self._lock.sync {
                    self._staging.flushed(change)
                }
            }
        }
    }

    /// Removes data for the given key. The method returns instantly, the data
    /// is removed asynchronously.
    public func removeData(for key: Key) {
        _lock.sync {
            let change = _staging.removeData(for: key)
            _wqueue.async {
                if let url = self._url(for: key) {
                    try? FileManager.default.removeItem(at: url)
                }
                self._lock.sync {
                    self._staging.flushed(change)
                }
            }
        }
    }

    /// Removes all items. The method returns instantly, the data is removed
    /// asynchronously.
    public func removeAll() {
        _lock.sync {
            let change = _staging.removeAll()
            _wqueue.async {
                try? FileManager.default.removeItem(at: self.path)
                try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
                self._lock.sync {
                    self._staging.flushed(change)
                }
            }
        }
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
            return cachedData(for: key)
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
        return _filenameGenerator(key)
    }

    /* testable */ func _url(for key: Key) -> URL? {
        guard let filename = self.filename(for: key) else {
            return nil
        }
        return self.path.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: Flush Changes

    /// Synchronously waits on the caller's thread until all outstanding disk IO
    /// operations are finished.
    func flush() {
        _wqueue.sync {}
    }

    // MARK: Sweep

    private func _performAndScheduleSweep() {
        _sweep()
        _wqueue.asyncAfter(deadline: .now() + sweepInterval) { [weak self] in
            self?._performAndScheduleSweep()
        }
    }

    /// Schedules a cache sweep to be performed immediately.
    public func sweep() {
        _wqueue.async {
            self._sweep()
        }
    }

    /// Discards the least recently used items first.
    private func _sweep() {
        var items = contents(keys: [.contentAccessDateKey, .totalFileAllocatedSizeKey])
        guard !items.isEmpty else {
            return
        }
        var size = items.reduce(0) { $0 + ($1.meta.totalFileAllocatedSize ?? 0) }
        var count = items.count
        let sizeLimit = self.sizeLimit / Int(1 / trimRatio)
        let countLimit = self.countLimit / Int(1 / trimRatio)

        guard size > sizeLimit || count > countLimit else {
            return // All good, no need to perform any work.
        }

        // Most recently accessed items first
        let past = Date.distantPast
        items.sort { // Sort in place
            ($0.meta.contentAccessDate ?? past) > ($1.meta.contentAccessDate ?? past)
        }

        // Remove the items until we satisfy both size and count limits.
        while (size > sizeLimit || count > countLimit), let item = items.popLast() {
            size -= (item.meta.totalFileAllocatedSize ?? 0)
            count -= 1
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
        let _keys = Set(keys)
        return urls.compactMap {
            guard let meta = try? $0.resourceValues(forKeys: _keys) else {
                return nil
            }
            return Entry(url: $0, meta: meta)
        }
    }

    // MARK: Inspection

    /// The total number of items in the cache.
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalCount: Int {
        return contents().count
    }

    /// The total file size of items written on disk.
    ///
    /// Uses `URLResourceKey.fileSizeKey` to calculate the size of each entry.
    /// The total allocated size (see `totalAllocatedSize`. on disk might
    /// actually be bigger.
    ///
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalSize: Int {
        return contents(keys: [.fileSizeKey]).reduce(0) {
            $0 + ($1.meta.fileSize ?? 0)
        }
    }

    /// The total file allocated size of all the items written on disk.
    ///
    /// Uses `URLResourceKey.totalFileAllocatedSizeKey`.
    ///
    /// - warning: Requires disk IO, avoid using from the main thread.
    public var totalAllocatedSize: Int {
        return contents(keys: [.totalFileAllocatedSizeKey]).reduce(0) {
            $0 + ($1.meta.totalFileAllocatedSize ?? 0)
        }
    }

    // MARK: - Staging

    /// DataCache allows for parallel reads and writes. This is made possible by
    /// DataCacheStaging.
    ///
    /// For example, when the data is added in cache, it is first added to staging
    /// and is removed from staging only after data is written to disk. Removal works
    /// the same way.
    private final class Staging {
        private var changes = [String: Change]()
        private var changeRemoveAll: ChangeRemoveAll?

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

        func add(data: Data, for key: String) -> Change {
            return _makeChange(.add(data), for: key)
        }

        func removeData(for key: String) -> Change {
            return _makeChange(.remove, for: key)
        }

        private func _makeChange(_ type: ChangeType, for key: String) -> Change {
            nextChangeId += 1
            let change = Change(key: key, id: nextChangeId, type: type)
            changes[key] = change
            return change
        }

        func removeAll() -> ChangeRemoveAll {
            nextChangeId += 1
            let change = ChangeRemoveAll(id: nextChangeId)
            changeRemoveAll = change
            changes.removeAll()
            return change
        }

        // MARK: Flush Changes

        func flushed(_ change: Change) {
            if let index = changes.index(forKey: change.key),
                changes[index].value.id == change.id {
                changes.remove(at: index)
            }
        }

        func flushed(_ change: ChangeRemoveAll) {
            if changeRemoveAll?.id == change.id {
                changeRemoveAll = nil
            }
        }
    }
}
