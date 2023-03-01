// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading, _DataLoaderObserving {
    public let session: URLSession
    private let impl = _DataLoader()

    public var observer: DataLoaderObserving?

    deinit {
        session.invalidateAndCancel()

        #if TRACK_ALLOCATIONS
        Allocations.decrement("DataLoader")
        #endif
    }

    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration,
                validate: @escaping (URLResponse) -> Swift.Error? = DataLoader.validate) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: impl, delegateQueue: queue)
        self.session.sessionDescription = "Nuke URLSession"
        self.impl.validate = validate
        self.impl.observer = self

        #if TRACK_ALLOCATIONS
        Allocations.increment("DataLoader")
        #endif
    }

    /// Returns a default configuration which has a `sharedUrlCache` set
    /// as a `urlCache`.
    public static var defaultConfiguration: URLSessionConfiguration {
        let conf = URLSessionConfiguration.default
        conf.urlCache = DataLoader.sharedUrlCache
        return conf
    }

    /// Validates `HTTP` responses by checking that the status code is 2xx. If
    /// it's not returns `DataLoader.Error.statusCodeUnacceptable`.
    public static func validate(response: URLResponse) -> Swift.Error? {
        guard let response = response as? HTTPURLResponse else {
            return nil
        }
        return (200..<300).contains(response.statusCode) ? nil : Error.statusCodeUnacceptable(response.statusCode)
    }

    #if !os(macOS) && !targetEnvironment(macCatalyst)
    private static let cachePath = "com.github.kean.Nuke.Cache"
    #else
    private static let cachePath: String = {
        let cachePaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        if let cachePath = cachePaths.first, let identifier = Bundle.main.bundleIdentifier {
            return cachePath.appending("/" + identifier)
        }

        return ""
    }()
    #endif

    /// Shared url cached used by a default `DataLoader`. The cache is
    /// initialized with 0 MB memory capacity and 150 MB disk capacity.
    public static let sharedUrlCache: URLCache = {
        let diskCapacity = 150 * 1024 * 1024 // 150 MB
        #if targetEnvironment(macCatalyst)
        return URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, directory: URL(fileURLWithPath: cachePath))
        #else
        return URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, diskPath: cachePath)
        #endif
    }()

    public func loadData(with request: URLRequest,
                         didReceiveData: @escaping (Data, URLResponse) -> Void,
                         completion: @escaping (Swift.Error?) -> Void) -> Cancellable {
        impl.loadData(with: request, session: session, didReceiveData: didReceiveData, completion: completion)
    }

    /// Errors produced by `DataLoader`.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// Validation failed.
        case statusCodeUnacceptable(Int)

        public var description: String {
            switch self {
            case let .statusCodeUnacceptable(code):
                return "Response status code was unacceptable: \(code.description)"
            }
        }
    }

    // MARK: _DataLoaderObserving

    func dataTask(_ dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent) {
        observer?.dataLoader(self, urlSession: session, dataTask: dataTask, didReceiveEvent: event)
    }
}

// Actual data loader implementation. Hide NSObject inheritance, hide
// URLSessionDataDelegate conformance, and break retain cycle between URLSession
// and URLSessionDataDelegate.
private final class _DataLoader: NSObject, URLSessionDataDelegate {
    var validate: (URLResponse) -> Swift.Error? = DataLoader.validate
    private var handlers = [URLSessionTask: _Handler]()
    weak var observer: _DataLoaderObserving?

    /// Loads data with the given request.
    func loadData(with request: URLRequest,
                  session: URLSession,
                  didReceiveData: @escaping (Data, URLResponse) -> Void,
                  completion: @escaping (Error?) -> Void) -> Cancellable {
        let task = session.dataTask(with: request)
        let handler = _Handler(didReceiveData: didReceiveData, completion: completion)
        session.delegateQueue.addOperation { // `URLSession` is configured to use this same queue
            self.handlers[task] = handler
        }
        task.taskDescription = "Nuke Load Data"
        task.resume()
        send(task, .resumed)
        return task
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        send(dataTask, .receivedResponse(response: response))

        guard let handler = handlers[dataTask] else {
            completionHandler(.cancel)
            return
        }
        if let error = validate(response) {
            handler.completion(error)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        assert(task is URLSessionDataTask)
        if let dataTask = task as? URLSessionDataTask {
            send(dataTask, .completed(error: error))
        }

        guard let handler = handlers[task] else {
            return
        }
        handlers[task] = nil
        handler.completion(error)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        send(dataTask, .receivedData(data: data))

        guard let handler = handlers[dataTask], let response = dataTask.response else {
            return
        }
        // Don't store data anywhere, just send it to the pipeline.
        handler.didReceiveData(data, response)
    }

    // MARK: Internal

    private func send(_ dataTask: URLSessionDataTask, _ event: DataTaskEvent) {
        observer?.dataTask(dataTask, didReceiveEvent: event)
    }

    private final class _Handler {
        let didReceiveData: (Data, URLResponse) -> Void
        let completion: (Error?) -> Void

        init(didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) {
            self.didReceiveData = didReceiveData
            self.completion = completion
        }
    }
}

// MARK: - DataLoaderObserving

/// An event send by the data loader.
public enum DataTaskEvent {
    case resumed
    case receivedResponse(response: URLResponse)
    case receivedData(data: Data)
    case completed(error: Error?)
}

/// Allows you to tap into internal events of the data loader. Events are
/// delivered on the internal serial operation queue.
public protocol DataLoaderObserving {
    func dataLoader(_ loader: DataLoader, urlSession: URLSession, dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent)
}

protocol _DataLoaderObserving: AnyObject {
    func dataTask(_ dataTask: URLSessionDataTask, didReceiveEvent event: DataTaskEvent)
}
