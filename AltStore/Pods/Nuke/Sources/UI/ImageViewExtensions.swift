// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if !os(macOS)
import UIKit.UIImage
import UIKit.UIColor
/// Alias for `UIImage`.
public typealias PlatformImage = UIImage
#else
import AppKit.NSImage
/// Alias for `NSImage`.
public typealias PlatformImage = NSImage
#endif

/// Displays images. Add the conformance to this protocol to your views to make
/// them compatible with Nuke image loading extensions.
///
/// The protocol is defined as `@objc` to make it possible to override its
/// methods in extensions (e.g. you can override `nuke_display(image:data:)` in
/// `UIImageView` subclass like `Gifu.ImageView).
///
/// The protocol and its methods have prefixes to make sure they don't clash
/// with other similar methods and protocol in Objective-C runtime.
@objc public protocol Nuke_ImageDisplaying {
    /// Display a given image.
    @objc func nuke_display(image: PlatformImage?, data: Data?)

    #if os(macOS)
    @objc var layer: CALayer? { get }
    #endif
}

extension Nuke_ImageDisplaying {
    func display(_ container: ImageContainer) {
        nuke_display(image: container.image, data: container.data)
    }
}

#if os(macOS)
public extension Nuke_ImageDisplaying {
    var layer: CALayer? { nil }
}
#endif

#if os(iOS) || os(tvOS)
import UIKit
/// A `UIView` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = UIView & Nuke_ImageDisplaying

extension UIImageView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?, data: Data? = nil) {
        self.image = image
    }
}
#elseif os(macOS)
import Cocoa
/// An `NSObject` that implements `ImageDisplaying`  and `Animating` protocols.
/// Can support `NSView` and `NSCell`. The latter can return nil for layer.
public typealias ImageDisplayingView = NSObject & Nuke_ImageDisplaying

extension NSImageView: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: NSImage?, data: Data? = nil) {
        self.image = image
    }
}
#elseif os(watchOS)
import WatchKit

/// A `WKInterfaceObject` that implements `ImageDisplaying` protocol.
public typealias ImageDisplayingView = WKInterfaceObject & Nuke_ImageDisplaying

extension WKInterfaceImage: Nuke_ImageDisplaying {
    /// Displays an image.
    open func nuke_display(image: UIImage?, data: Data? = nil) {
        self.setImage(image)
    }
}
#endif

// MARK: - ImageView Extensions

/// Loads an image with the given request and displays it in the view.
///
/// See the complete method signature for more information.
@discardableResult
public func loadImage(
    with request: ImageRequestConvertible?,
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    completion: @escaping (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
) -> ImageTask? {
    loadImage(with: request, options: options, into: view, progress: nil, completion: completion)
}

/// Loads an image with the given request and displays it in the view.
///
/// Before loading a new image, the view is prepared for reuse by canceling any
/// outstanding requests and removing a previously displayed image.
///
/// If the image is stored in the memory cache, it is displayed immediately with
/// no animations. If not, the image is loaded using an image pipeline. When the
/// image is loading, the `placeholder` is displayed. When the request
/// completes the loaded image is displayed (or `failureImage` in case of an error)
/// with the selected animation.
///
/// - parameter request: The image request. If `nil`, it's handled as a failure
/// scenario.
/// - parameter options: `ImageLoadingOptions.shared` by default.
/// - parameter view: Nuke keeps a weak reference to the view. If the view is deallocated
/// the associated request automatically gets canceled.
/// - parameter progress: A closure to be called periodically on the main thread
/// when the progress is updated. `nil` by default.
/// - parameter completion: A closure to be called on the main thread when the
/// request is finished. Gets called synchronously if the response was found in
/// the memory cache. `nil` by default.
/// - returns: An image task or `nil` if the image was found in the memory cache.
@discardableResult
public func loadImage(
    with request: ImageRequestConvertible?,
    options: ImageLoadingOptions = ImageLoadingOptions.shared,
    into view: ImageDisplayingView,
    progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
    completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
) -> ImageTask? {
    assert(Thread.isMainThread)
    let controller = ImageViewController.controller(for: view)
    return controller.loadImage(with: request?.asImageRequest(), options: options, progress: progress, completion: completion)
}

/// Cancels an outstanding request associated with the view.
public func cancelRequest(for view: ImageDisplayingView) {
    assert(Thread.isMainThread)
    ImageViewController.controller(for: view).cancelOutstandingTask()
}

// MARK: - ImageLoadingOptions

/// A set of options that control how the image is loaded and displayed.
public struct ImageLoadingOptions {
    /// Shared options.
    public static var shared = ImageLoadingOptions()

    /// Placeholder to be displayed when the image is loading. `nil` by default.
    public var placeholder: PlatformImage?

    /// Image to be displayed when the request fails. `nil` by default.
    public var failureImage: PlatformImage?

    #if os(iOS) || os(tvOS) || os(macOS)

    /// The image transition animation performed when displaying a loaded image.
    /// Only runs when the image was not found in memory cache. `nil` by default.
    public var transition: Transition?

    /// The image transition animation performed when displaying a failure image.
    /// `nil` by default.
    public var failureImageTransition: Transition?

    /// If true, the requested image will always appear with transition, even
    /// when loaded from cache.
    public var alwaysTransition = false

    func transition(for response: ResponseType) -> Transition? {
        switch response {
        case .success: return transition
        case .failure: return failureImageTransition
        case .placeholder: return nil
        }
    }

    #endif

    /// If true, every time you request a new image for a view, the view will be
    /// automatically prepared for reuse: image will be set to `nil`, and animations
    /// will be removed. `true` by default.
    public var isPrepareForReuseEnabled = true

    /// If `true`, every progressively generated preview produced by the pipeline
    /// is going to be displayed. `true` by default.
    ///
    /// - note: To enable progressive decoding, see `ImagePipeline.Configuration`,
    /// `isProgressiveDecodingEnabled` option.
    public var isProgressiveRenderingEnabled = true

    /// Custom pipeline to be used. `nil` by default.
    public var pipeline: ImagePipeline?

    /// Image processors to be applied unless the processors are provided in the
    /// request. `[]` by default.
    public var processors: [ImageProcessing] = []

    #if os(iOS) || os(tvOS)

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

    func contentMode(for response: ResponseType) -> UIView.ContentMode? {
        switch response {
        case .success: return contentModes?.success
        case .placeholder: return contentModes?.placeholder
        case .failure: return contentModes?.failure
        }
    }

    /// Tint colors to be used for each image type (placeholder, success,
    /// failure). `nil`  by default (don't change tint color or rendering mode).
    public var tintColors: TintColors?

    /// Custom tint color to be used for each image type (placeholder, success,
    /// failure).
    public struct TintColors {
        /// Tint color to be used for the loaded image.
        public var success: UIColor?
        /// Tint color to be used when displaying a `failureImage`.
        public var failure: UIColor?
        /// Tint color to be used when displaying a `placeholder`.
        public var placeholder: UIColor?

        /// - parameter success: A tint color to be used with a loaded image.
        /// - parameter failure: A tint color to be used with a `failureImage`.
        /// - parameter placeholder: A tint color to be used with a `placeholder`.
        public init(success: UIColor?, failure: UIColor?, placeholder: UIColor?) {
            self.success = success; self.failure = failure; self.placeholder = placeholder
        }
    }

    func tintColor(for response: ResponseType) -> UIColor? {
        switch response {
        case .success: return tintColors?.success
        case .placeholder: return tintColors?.placeholder
        case .failure: return tintColors?.failure
        }
    }

    #endif

    #if os(iOS) || os(tvOS)

    /// - parameter placeholder: Placeholder to be displayed when the image is
    /// loading . `nil` by default.
    /// - parameter transition: The image transition animation performed when
    /// displaying a loaded image. Only runs when the image was not found in
    /// memory cache. `nil` by default (no animations).
    /// - parameter failureImage: Image to be displayd when request fails.
    /// `nil` by default.
    /// - parameter failureImageTransition: The image transition animation
    /// performed when displaying a failure image. `nil` by default.
    /// - parameter contentModes: Content modes to be used for each image type
    /// (placeholder, success, failure). `nil` by default (don't change content mode).
    public init(placeholder: UIImage? = nil, transition: Transition? = nil, failureImage: UIImage? = nil, failureImageTransition: Transition? = nil, contentModes: ContentModes? = nil, tintColors: TintColors? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
        self.contentModes = contentModes
        self.tintColors = tintColors
    }

    #elseif os(macOS)

    public init(placeholder: NSImage? = nil, transition: Transition? = nil, failureImage: NSImage? = nil, failureImageTransition: Transition? = nil) {
        self.placeholder = placeholder
        self.transition = transition
        self.failureImage = failureImage
        self.failureImageTransition = failureImageTransition
    }

    #elseif os(watchOS)

    public init(placeholder: UIImage? = nil, failureImage: UIImage? = nil) {
        self.placeholder = placeholder
        self.failureImage = failureImage
    }

    #endif

    /// An animated image transition.
    public struct Transition {
        var style: Style

        #if os(iOS) || os(tvOS)
        enum Style { // internal representation
            case fadeIn(parameters: Parameters)
            case custom((ImageDisplayingView, UIImage) -> Void)
        }

        struct Parameters { // internal representation
            let duration: TimeInterval
            let options: UIView.AnimationOptions
        }

        /// Fade-in transition (cross-fade in case the image view is already
        /// displaying an image).
        public static func fadeIn(duration: TimeInterval, options: UIView.AnimationOptions = .allowUserInteraction) -> Transition {
            Transition(style: .fadeIn(parameters: Parameters(duration: duration, options: options)))
        }

        /// Custom transition. Only runs when the image was not found in memory cache.
        public static func custom(_ closure: @escaping (ImageDisplayingView, UIImage) -> Void) -> Transition {
            Transition(style: .custom(closure))
        }
        #elseif os(macOS)
        enum Style { // internal representation
            case fadeIn(parameters: Parameters)
            case custom((ImageDisplayingView, NSImage) -> Void)
        }

        struct Parameters { // internal representation
            let duration: TimeInterval
        }

        /// Fade-in transition.
        public static func fadeIn(duration: TimeInterval) -> Transition {
            Transition(style: .fadeIn(parameters: Parameters(duration: duration)))
        }

        /// Custom transition. Only runs when the image was not found in memory cache.
        public static func custom(_ closure: @escaping (ImageDisplayingView, NSImage) -> Void) -> Transition {
            Transition(style: .custom(closure))
        }
        #else
        enum Style {}
        #endif
    }

    public init() {}

    enum ResponseType {
        case success, failure, placeholder
    }
}

// MARK: - ImageViewController

/// Manages image requests on behalf of an image view.
///
/// - note: With a few modifications this might become public at some point,
/// however as it stands today `ImageViewController` is just a helper class,
/// making it public wouldn't expose any additional functionality to the users.
private final class ImageViewController {
    private weak var imageView: ImageDisplayingView?
    private var task: ImageTask?
    private var options: ImageLoadingOptions

    #if os(iOS) || os(tvOS)
    // Image view used for cross-fade transition between images with different
    // content modes.
    private lazy var transitionImageView = UIImageView()
    #endif

    // Automatically cancel the request when the view is deallocated.
    deinit {
        cancelOutstandingTask()
    }

    init(view: /* weak */ ImageDisplayingView) {
        self.imageView = view
        self.options = .shared
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

    func loadImage(
        with request: ImageRequest?,
        options: ImageLoadingOptions,
        progress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)? = nil,
        completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil
    ) -> ImageTask? {
        cancelOutstandingTask()

        guard let imageView = imageView else {
            return nil
        }

        self.options = options

        if options.isPrepareForReuseEnabled { // enabled by default
            #if os(iOS) || os(tvOS)
            imageView.layer.removeAllAnimations()
            #elseif os(macOS)
            let layer = (imageView as? NSView)?.layer ?? imageView.layer
            layer?.removeAllAnimations()
            #endif
        }

        // Handle a scenario where request is `nil` (in the same way as a failure)
        guard let unwrappedRequest = request else {
            if options.isPrepareForReuseEnabled {
                imageView.nuke_display(image: nil, data: nil)
            }
            let result: Result<ImageResponse, ImagePipeline.Error> = .failure(.dataLoadingFailed(URLError(.unknown)))
            handle(result: result, isFromMemory: true)
            completion?(result)
            return nil
        }

        let pipeline = options.pipeline ?? ImagePipeline.shared
        var request = pipeline.configuration.inheritOptions(unwrappedRequest)
        if !options.processors.isEmpty && request.processors.isEmpty {
            request.processors = options.processors
        }

        // Quick synchronous memory cache lookup.
        if let image = pipeline.cache[request] {
            display(image, true, .success)
            if !image.isPreview { // Final image was downloaded
                completion?(.success(ImageResponse(container: image, cacheType: .memory)))
                return nil // No task to perform
            }
        }

        // Display a placeholder.
        if let placeholder = options.placeholder {
            display(ImageContainer(image: placeholder), true, .placeholder)
        } else if options.isPrepareForReuseEnabled {
            imageView.nuke_display(image: nil, data: nil) // Remove previously displayed images (if any)
        }

        task = pipeline.loadImage(with: request, queue: .main, progress: { [weak self] response, completedCount, totalCount in
            if let response = response, options.isProgressiveRenderingEnabled {
                self?.handle(partialImage: response)
            }
            progress?(response, completedCount, totalCount)
        }, completion: { [weak self] result in
            self?.handle(result: result, isFromMemory: false)
            completion?(result)
        })
        return task
    }

    func cancelOutstandingTask() {
        task?.cancel() // The pipeline guarantees no callbacks to be deliver after cancellation
        task = nil
    }

    // MARK: - Handling Responses

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>, isFromMemory: Bool) {
        switch result {
        case let .success(response):
            display(response.container, isFromMemory, .success)
        case .failure:
            if let failureImage = options.failureImage {
                display(ImageContainer(image: failureImage), isFromMemory, .failure)
            }
        }
        self.task = nil
    }

    private func handle(partialImage response: ImageResponse) {
        display(response.container, false, .success)
    }

    #if os(iOS) || os(tvOS) || os(macOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        guard let imageView = imageView else {
            return
        }

        var image = image

        #if os(iOS) || os(tvOS)
        if let tintColor = options.tintColor(for: response) {
            image = image.map { $0.withRenderingMode(.alwaysTemplate) } ?? image
            imageView.tintColor = tintColor
        }
        #endif

        if !isFromMemory || options.alwaysTransition, let transition = options.transition(for: response) {
            switch transition.style {
            case let .fadeIn(params):
                runFadeInTransition(image: image, params: params, response: response)
            case let .custom(closure):
                // The user is reponsible for both displaying an image and performing
                // animations.
                closure(imageView, image.image)
            }
        } else {
            imageView.display(image)
        }

        #if os(iOS) || os(tvOS)
        if let contentMode = options.contentMode(for: response) {
            imageView.contentMode = contentMode
        }
        #endif
    }

    #elseif os(watchOS)

    private func display(_ image: ImageContainer, _ isFromMemory: Bool, _ response: ImageLoadingOptions.ResponseType) {
        imageView?.display(image)
    }

    #endif
}

// MARK: - ImageViewController (Transitions)

private extension ImageViewController {
    #if os(iOS) || os(tvOS)

    private func runFadeInTransition(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters, response: ImageLoadingOptions.ResponseType) {
        guard let imageView = imageView else {
            return
        }

        // Special case where it animates between content modes, only works
        // on imageView subclasses.
        if let contentMode = options.contentMode(for: response), imageView.contentMode != contentMode, let imageView = imageView as? UIImageView, imageView.image != nil {
            runCrossDissolveWithContentMode(imageView: imageView, image: image, params: params)
        } else {
            runSimpleFadeIn(image: image, params: params)
        }
    }

    private func runSimpleFadeIn(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters) {
        guard let imageView = imageView else {
            return
        }

        UIView.transition(
            with: imageView,
            duration: params.duration,
            options: params.options.union(.transitionCrossDissolve),
            animations: {
                imageView.nuke_display(image: image.image, data: image.data)
            },
            completion: nil
        )
    }

    /// Performs cross-dissolve animation alonside transition to a new content
    /// mode. This isn't natively supported feature and it requires a second
    /// image view. There might be better ways to implement it.
    private func runCrossDissolveWithContentMode(imageView: UIImageView, image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters) {
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
        imageView.display(image) // Display new image in current view

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

    #elseif os(macOS)

    private func runFadeInTransition(image: ImageContainer, params: ImageLoadingOptions.Transition.Parameters, response: ImageLoadingOptions.ResponseType) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = params.duration
        animation.fromValue = 0
        animation.toValue = 1
        imageView?.layer?.add(animation, forKey: "imageTransition")

        imageView?.display(image)
    }

    #endif
}
