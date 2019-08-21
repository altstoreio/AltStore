// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
/// Alias for `UIImage`.
public typealias Image = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias Image = NSImage
#endif

#if !os(watchOS)

/// Displays images. Adopt this protocol in views to make them compatible with
/// Nuke APIs.
///
/// The protocol is defined as `@objc` to enable users to override its methods
/// in extensions (e.g. you can override `display(image:)` in `UIImageView` subclass).
@objc public protocol ImageDisplaying {
    @objc func display(image: Image?)
}

#if !os(macOS)
import UIKit
/// A `UIView` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = UIView & ImageDisplaying

extension UIImageView: ImageDisplaying {
    /// Displays an image.
    open func display(image: Image?) {
        self.image = image
    }
}
#else
import Cocoa
/// An `NSView` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = NSView & ImageDisplaying

extension NSImageView: ImageDisplaying {
    /// Displays an image.
    open func display(image: Image?) {
        self.image = image
    }
}
#endif

/// Loads an image into the view.
///
/// Before loading the new image prepares the view for reuse by cancelling any
/// outstanding requests and removing previously displayed images (if any).
///
/// If the image is stored in memory cache, the image is displayed immediately.
/// If not, the image is loaded using an image pipeline. Displays a `placeholder`
/// if it was provided. When the request completes the loaded image is displayed
/// (or `failureImage` in case of an error).
///
/// Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets cancelled.
///
/// - parameter options: `ImageLoadingOptions.shared` by default.
/// - parameter progress: A closure to be called periodically on the main thread
/// when the progress is updated. `nil` by default.
/// - parameter completion: A closure to be called on the main thread when the
/// request is finished. Gets called synchronously if the response was found in
/// memory cache. `nil` by default.
/// - returns: An image task of `nil` if the image was found in memory cache.
@discardableResult
public func loadImage(with url: URL,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      progress: ImageTask.ProgressHandler? = nil,
                      completion: ImageTask.Completion? = nil) -> ImageTask? {
    return loadImage(with: ImageRequest(url: url), options: options, into: view, progress: progress, completion: completion)
}

/// Loads an image into the view.
///
/// Before loading the new image prepares the view for reuse by cancelling any
/// outstanding requests and removing previously displayed images (if any).
///
/// If the image is stored in memory cache, the image is displayed immediately.
/// If not, the image is loaded using an image pipeline. Displays a `placeholder`
/// if it was provided. When the request completes the loaded image is displayed
/// (or `failureImage` in case of an error).
///
/// Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets cancelled.
///
/// - parameter options: `ImageLoadingOptions.shared` by default.
/// - parameter progress: A closure to be called periodically on the main thread
/// when the progress is updated. `nil` by default.
/// - parameter completion: A closure to be called on the main thread when the
/// request is finished. Gets called synchronously if the response was found in
/// memory cache. `nil` by default.
/// - returns: An image task of `nil` if the image was found in memory cache.
@discardableResult
public func loadImage(with request: ImageRequest,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      progress: ImageTask.ProgressHandler? = nil,
                      completion: ImageTask.Completion? = nil) -> ImageTask? {
    assert(Thread.isMainThread)
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: request, options: options, progress: progress, completion: completion)
}

/// Cancels an outstanding request associated with the view.
public func cancelRequest(for view: ImageDisplayingView) {
    assert(Thread.isMainThread)
    ImageViewController.controller(for: view).cancelOutstandingTask()
}

// MARK: - ImageLoadingOptions

/// A range of options that control how the image is loaded and displayed.
public struct ImageLoadingOptions {
    /// Shared options.
    public static var shared = ImageLoadingOptions()

    /// Placeholder to be displayed when the image is loading. `nil` by default.
    public var placeholder: Image?

    /// The image transition animation performed when displaying a loaded image.
    /// Only runs when the image was not found in memory cache. `.nil` by default.
    public var transition: Transition?

    /// Image to be displayed when the request fails. `nil` by default.
    public var failureImage: Image?

    /// The image transition animation performed when displaying a failure image.
    /// `.nil` by default.
    public var failureImageTransition: Transition?
    
    /// If true, the requested image will always appear with transition, even
    /// when loaded from cache
    public var alwaysTransition = false

    /// If true, every time you request a new image for a view, the view will be
    /// automatically prepared for reuse: image will be set to `nil`, and animations
    /// will be removed. `true` by default.
    public var isPrepareForReuseEnabled = true

    /// Custom pipeline to be used. `nil` by default.
    public var pipeline: ImagePipeline?

    #if !os(macOS)
    /// Content modes to be used for each image type (placeholder, success,
    /// failure). `nil`  by default (don't change content mode).
    public var contentModes: ContentModes?

    /// Custom content modes to be used for each image type (placeholder, success,
    /// failure).
    public struct ContentModes {
        /// Content mode to be used for the loaded image.
        public var success: UIView.ContentMode
        /// Content mode to be used when displaying a `failureImage`.
        public var failure: UIView.ContentMode
        /// Content mode to be used when displaying a `placeholder`.
        public var placeholder: UIView.ContentMode

        /// - parameter success: A content mode to be used with a loaded image.
        /// - parameter failure: A content mode to be used with a `failureImage`.
        /// - parameter placeholder: A content mode to be used with a `placeholder`.
        public init(success: UIView.ContentMode, failure: UIView.ContentMode, placeholder: UIView.ContentMode) {
            self.success = success; self.failure = failure; self.placeholder = placeholder
        }
    }

    /// - parameter placeholder: Placeholder to be displayed when the image is
    /// loading . `nil` by default.
    /// - parameter transision: The image transition animation performed when
    /// displaying a loaded image. Only runs when the image was not found in
    /// memory cache `.nil` by default (no animations).
    /// - parameter failureImage: Image to be displayd when request fails.
    /// `nil` by default.
    /// - parameter failureImageTransition: The image transition animation
    /// performed when displaying a failure image. `.nil` by default.
    /// - parameter contentModes: Content modes to be used for each image type
    /// (placeholder, success, failure). `nil` by default (don't change content mode).
    public init(placeholder: Image? = nil, transition: Transition? = nil, failureImage: Image? = nil, failureImageTransition: Transition? = nil, contentModes: ContentModes? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
        self.contentModes = contentModes
    }
    #else
    public init(placeholder: Image? = nil, transition: Transition? = nil, failureImage: Image? = nil, failureImageTransition: Transition? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
    }
    #endif

    /// An animated image transition.
    public struct Transition {
        var style: Style

        struct Parameters { // internal representation
            let duration: TimeInterval
            #if !os(macOS)
            let options: UIView.AnimationOptions
            #endif
        }

        enum Style { // internal representation
            case fadeIn(parameters: Parameters)
            case custom((ImageDisplayingView, Image) -> Void)
        }

        #if !os(macOS)
        /// Fade-in transition (cross-fade in case the image view is already
        /// displaying an image).
        public static func fadeIn(duration: TimeInterval, options: UIView.AnimationOptions = .allowUserInteraction) -> Transition {
            return Transition(style: .fadeIn(parameters:  Parameters(duration: duration, options: options)))
        }
        #else
        /// Fade-in transition.
        public static func fadeIn(duration: TimeInterval) -> Transition {
            return Transition(style: .fadeIn(parameters:  Parameters(duration: duration)))
        }
        #endif

        /// Custom transition. Only runs when the image was not found in memory cache.
        public static func custom(_ closure: @escaping (ImageDisplayingView, Image) -> Void) -> Transition {
            return Transition(style: .custom(closure))
        }
    }

    public init() {}
}

// MARK: - ImageViewController

/// Manages image requests on behalf of an image view.
///
/// - note: With a few modifications this might become public at some point,
/// however as it stands today `ImageViewController` is just a helper class,
/// making it public wouldn't expose any additional functionality to the users.
private final class ImageViewController {
    // Ideally should be `unowned` but can't because of the Swift bug
    // https://bugs.swift.org/browse/SR-7369
    private weak var imageView: ImageDisplayingView?
    private weak var task: ImageTask?
    private var taskId: Int = 0

    // Automatically cancel the request when the view is deallocated.
    deinit {
        cancelOutstandingTask()
    }

    init(view: /* weak */ ImageDisplayingView) {
        self.imageView = view
    }

    // MARK: - Associating Controller

    static var controllerAK = "ImageViewController.AssociatedKey"

    // Lazily create a controller for a given view and associate it with a view.
    static func controller(for view: ImageDisplayingView) -> ImageViewController {
        if let controller = objc_getAssociatedObject(view, &ImageViewController.controllerAK) as? ImageViewController {
            return controller
        }
        let controller = ImageViewController(view: view)
        objc_setAssociatedObject(view, &ImageViewController.controllerAK, controller, .OBJC_ASSOCIATION_RETAIN)
        return controller
    }

    // MARK: - Loading Images

    func loadImage(with request: ImageRequest,
                   options: ImageLoadingOptions,
                   progress: ImageTask.ProgressHandler? = nil,
                   completion: ImageTask.Completion? = nil) -> ImageTask? {
        cancelOutstandingTask()

        guard let imageView = imageView else {
            return nil
        }

        if options.isPrepareForReuseEnabled { // enabled by default
            #if !os(macOS)
            imageView.layer.removeAllAnimations()
            #else
            imageView.layer?.removeAllAnimations()
            #endif
        }

        let pipeline = options.pipeline ?? ImagePipeline.shared

        // Quick synchronous memory cache lookup
        if request.memoryCacheOptions.isReadAllowed,
            let imageCache = pipeline.configuration.imageCache,
            let response = imageCache.cachedResponse(for: request) {
            handle(response: response, error: nil, fromMemCache: true, options: options)
            completion?(response, nil)
            return nil
        }

        // Display a placeholder.
        if let placeholder = options.placeholder {
            imageView.display(image: placeholder)
            #if !os(macOS)
            if let contentMode = options.contentModes?.placeholder {
                imageView.contentMode = contentMode
            }
            #endif
        } else {
            if options.isPrepareForReuseEnabled {
                imageView.display(image: nil) // Remove previously displayed images (if any)
            }
        }

        // Makes sure that view reuse is handled correctly.
        let taskId = self.taskId

        // Start the request.
        self.task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard self?.taskId == taskId else { return }
                self?.handle(partialImage: response, options: options)
                progress?(response, completed, total)
            },
            completion: { [weak self] response, error in
                guard self?.taskId == taskId else { return }
                self?.handle(response: response, error: error, fromMemCache: false, options: options)
                completion?(response, error)
            }
        )
        return self.task
    }

    func cancelOutstandingTask() {
        taskId += 1
        task?.cancel()
        task = nil
    }

    // MARK: - Handling Responses

    #if !os(macOS)

    private func handle(response: ImageResponse?, error: Error?, fromMemCache: Bool, options: ImageLoadingOptions) {
        if let image = response?.image {
            _display(image, options.transition, options.alwaysTransition, fromMemCache, options.contentModes?.success)
        } else if let failureImage = options.failureImage {
            _display(failureImage, options.failureImageTransition, options.alwaysTransition, fromMemCache, options.contentModes?.failure)
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse?, options: ImageLoadingOptions) {
        guard let image = response?.image else { return }
        _display(image, options.transition, options.alwaysTransition, false, options.contentModes?.success)
    }

    private func _display(_ image: Image, _ transition: ImageLoadingOptions.Transition?, _ alwaysTransition: Bool, _ fromMemCache: Bool, _ newContentMode: UIView.ContentMode?) {
        guard let imageView = imageView else { return }

        if !fromMemCache || alwaysTransition, let transition = transition {
            switch transition.style {
            case let .fadeIn(params):
                _runFadeInTransition(image: image, params: params, contentMode: newContentMode)
            case let .custom(closure):
                // The user is reponsible for both displaying an image and performing
                // animations.
                closure(imageView, image)
            }
        } else {
            imageView.display(image: image)
        }
        if let newContentMode = newContentMode {
            imageView.contentMode = newContentMode
        }
    }

    // Image view used for cross-fade transition between images with different
    // content modes.
    private lazy var transitionImageView = UIImageView()

    private func _runFadeInTransition(image: Image, params: ImageLoadingOptions.Transition.Parameters, contentMode: UIView.ContentMode?) {
        guard let imageView = imageView else { return }

        // Special case where we animate between content modes, only works
        // on imageView subclasses.
        if let contentMode = contentMode, imageView.contentMode != contentMode, let imageView = imageView as? UIImageView, imageView.image != nil {
            _runCrossDissolveWithContentMode(imageView: imageView, image: image, params: params)
        } else {
            _runSimpleFadeIn(image: image, params: params)
        }
    }

    private func _runSimpleFadeIn(image: Image, params: ImageLoadingOptions.Transition.Parameters) {
        guard let imageView = imageView else { return }

        UIView.transition(
            with: imageView,
            duration: params.duration,
            options: params.options.union(.transitionCrossDissolve),
            animations: {
                imageView.display(image: image)
        },
            completion: nil
        )
    }

    /// Performs cross-dissolve animation alonside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    private func _runCrossDissolveWithContentMode(imageView: UIImageView, image: Image, params: ImageLoadingOptions.Transition.Parameters) {
        // Lazily create a transition view.
        let transitionView = self.transitionImageView

        // Create a transition view which mimics current view's contents.
        transitionView.image = imageView.image
        transitionView.contentMode = imageView.contentMode
        imageView.addSubview(transitionView)
        transitionView.frame = imageView.bounds

        // "Manual" cross-fade.
        transitionView.alpha = 1
        imageView.alpha = 0
        imageView.image = image // Display new image in current view

        UIView.animate(
            withDuration: params.duration,
            delay: 0,
            options: params.options,
            animations: {
                transitionView.alpha = 0
                imageView.alpha = 1
        },
            completion: { isCompleted in
                if isCompleted {
                    transitionView.removeFromSuperview()
                }
        }
        )
    }

    #else

    private func handle(response: ImageResponse?, error: Error?, fromMemCache: Bool, options: ImageLoadingOptions) {
        // NSImageView doesn't support content mode, unfortunately.
        if let image = response?.image {
            _display(image, options.transition, options.alwaysTransition, fromMemCache)
        } else if let failureImage = options.failureImage {
            _display(failureImage, options.failureImageTransition, options.alwaysTransition, fromMemCache)
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse?, options: ImageLoadingOptions) {
        guard let image = response?.image else { return }
        _display(image, options.transition, options.alwaysTransition, false)
    }

    private func _display(_ image: Image, _ transition: ImageLoadingOptions.Transition?, _ alwaysTransition: Bool, _ fromMemCache: Bool) {
        guard let imageView = imageView else { return }

        if !fromMemCache || alwaysTransition, let transition = transition {
            switch transition.style {
            case let .fadeIn(params):
                _runFadeInTransition(image: image, params: params)
            case let .custom(closure):
                // The user is reponsible for both displaying an image and performing
                // animations.
                closure(imageView, image)
            }
        } else {
            imageView.display(image: image)
        }
    }

    private func _runFadeInTransition(image: Image, params: ImageLoadingOptions.Transition.Parameters) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = params.duration
        animation.fromValue = 0
        animation.toValue = 1
        imageView?.layer?.add(animation, forKey: "imageTransition")

        imageView?.display(image: image)
    }

    #endif
}

#endif
