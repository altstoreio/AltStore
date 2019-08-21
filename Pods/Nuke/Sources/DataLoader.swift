// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol Cancellable: class {
    func cancel()
}

public protocol DataLoading {
    /// - parameter didReceiveData: Can be called multiple times if streaming
    /// is supported.
    /// - parameter completion: Must be called once after all (or none in case
    /// of an error) `didReceiveData` closures have been called.
    func loadData(with request: URLRequest,
                  didReceiveData: @escaping (Data, URLResponse) -> Void,
                  completion: @escaping (Error?) -> Void) -> Cancellable
}

extension URLSessionTask: Cancellable {}

/// Provides basic networking using `URLSession`.
public final class DataLoader: DataLoading {
    public let session: URLSession
    private let _impl: _DataLoader

    /// Initializes `DataLoader` with the given configuration.
    /// - parameter configuration: `URLSessionConfiguration.default` with
    /// `URLCache` with 0 MB memory capacity and 150 MB disk capacity.
    public init(configuration: URLSessionConfiguration = DataLoader.defaultConfiguration,
                validate: @escaping (URLResponse) -> Swift.Error? = DataLoader.validate) {
        self._impl = _DataLoader()
        self.session = URLSession(configuration: configuration, delegate: _impl, delegateQueue: _impl.queue)
        self._impl.session = self.session
        self._impl.validate = validate
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
        guard let response = response as? HTTPURLResponse else { return nil }
        return (200..<300).contains(response.statusCode) ? nil : Error.statusCodeUnacceptable(response.statusCode)
    }

#if !os(macOS)
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
    public static let sharedUrlCache = URLCache(
        memoryCapacity: 0,
        diskCapacity: 150 * 1024 * 1024, // 150 MB
        diskPath: cachePath
    )

    public func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Swift.Error?) -> Void) -> Cancellable {
        return _impl.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
    }

    /// Errors produced by `DataLoader`.
    public enum Error: Swift.Error, CustomDebugStringConvertible {
        /// Validation failed.
        case statusCodeUnacceptable(Int)
        /// Either the response or body was empty.
        @available(*, deprecated, message: "This error case is not used any more")
        case responseEmpty

        public var debugDescription: String {
            switch self {
            case let .statusCodeUnacceptable(code): return "Response status code was unacceptable: " + code.description // compiles faster than interpolation
            case .responseEmpty: return "Either the response or body was empty."
            }
        }
    }
}

// Actual data loader implementation. We hide NSObject inheritance, hide
// URLSessionDataDelegate conformance, and break retain cycle between URLSession
// and URLSessionDataDelegate.
private final class _DataLoader: NSObject, URLSessionDataDelegate {
    weak var session: URLSession! // This is safe.
    var validate: (URLResponse) -> Swift.Error? = DataLoader.validate
    let queue = OperationQueue()

    private var handlers = [URLSessionTask: _Handler]()

    override init() {
        self.queue.maxConcurrentOperationCount = 1
    }

    /// Loads data with the given request.
    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let task = session.dataTask(with: request)
        let handler = _Handler(didReceiveData: didReceiveData, completion: completion)
        queue.addOperation { // `URLSession` is configured to use this same queue
            self.handlers[task] = handler
        }
        task.resume()
        return task
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let handler = handlers[dataTask] else {
            completionHandler(.cancel)
            return
        }
        // Validate response as soon as we receive it can cancel the request if necessary
        if let error = validate(response) {
            handler.completion(error)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = handlers[task] else { return }
        handlers[task] = nil
        handler.completion(error)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handler = handlers[dataTask], let response = dataTask.response else { return }
        // We don't store data anywhere, just send it to the pipeline.
        handler.didReceiveData(data, response)
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
