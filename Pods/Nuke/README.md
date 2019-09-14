<br/>

<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/supports-CocoaPods%2C%20Carthage%2C%20SwiftPM-green.svg">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
</p>

A powerful **image loading** and **caching** system.

- Fast LRU memory cache, native HTTP disk cache, and custom aggressive LRU disk cache
- Progressive image loading (progressive JPEG and WebP)
- Resumable downloads, request prioritization, deduplication, rate limiting and more
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [WebP](https://github.com/ryokosuge/Nuke-WebP-Plugin), [Gifu](https://github.com/kean/Nuke-Gifu-Plugin), [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin) extensions
- [RxNuke](https://github.com/kean/RxNuke) - [RxSwift](https://github.com/ReactiveX/RxSwift) extensions
- Automates [prefetching](https://kean.github.io/post/image-preheating) with [Preheat](https://github.com/kean/Preheat) (*deprecated in iOS 10*)

# <a name="h_getting_started"></a>Getting Started

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).

- [**Quick Start Guide**](#h_usage)
  - [Load Image into Image View](#load-image-into-image-view)
  - [Placeholders, Transitions and More](#placeholders-transitions-and-more)
  - [Image Requests](#image-requests), [Process an Image](#process-an-image)
- [**Advanced Usage Guide**](#advanced-usage)
  - [Image Pipeline](#image-pipeline), [Configuring Image Pipeline](#configuring-image-pipeline)
  - [Memory Cache](#memory-cache), [HTTP Disk Cache](#http-disk-cache), [Aggressive Disk Cache](#aggressive-disk-cache)
  - [Preheat Images](#preheat-images)
  - [Progressive Decoding](#progressive-decoding), [Animated Images](#animated-images), [WebP](#webp)
  - [RxNuke](#rxnuke)
- Detailed [**Image Pipeline**](#h_design) description
- An entire section dedicated to [**Performance**](#h_performance)
- List of [**Extensions**](#h_plugins)
- [**Contributing**](#h_contribute) and roadmap
- [**Requirements**](#h_requirements)

More information is available in [**Documentation**](https://github.com/kean/Nuke/blob/master/Documentation/) directory and a full [**API Reference**](https://kean.github.io/Nuke/reference/7.3/index.html). When you are ready to install Nuke you can follow an [**Installation Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md) - all major package managers are supported.

# <a name="h_usage"></a>Quick Start

#### Load Image into Image View

You can load an image into an image view with a single line of code.

```swift
Nuke.loadImage(with: url, into: imageView)
```

Nuke will automatically load image data, decompress it in the background, store image in memory cache and display it.

> To learn more about the `ImagePipeline` [see the dedicated section](#h_design).

When you request a new image for the view, the previous outstanding request gets canceled and the image is set to `nil`. The request also gets canceled automatically when the view is deallocated.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    ...
    Nuke.loadImage(with: url, into: cell.imageView)
    ...
}
```

#### Placeholders, Transitions and More

Use an  `options` parameter (`ImageLoadingOptions`)  to customize the way images are loaded and displayed. You can provide a placeholder, select one of the built-in transitions or provide a custom one. When using transitions, be aware that UIKit may keep a reference to the image, preventing it from being removed for long animations or loading many transitions at once.

```swift
Nuke.loadImage(
    with: url,
    options: ImageLoadingOptions(
        placeholder: UIImage(named: "placeholder"),
        transition: .fadeIn(duration: 0.33)
    ),
    into: imageView
)
```

There is a very common scenario when the placeholder (or the failure image) needs to be displayed with a _content mode_ different from the one used for the loaded image.

```swift
let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    failureImage: UIImage(named: "failure_image"),
    contentModes: .init(
        success: .scaleAspectFill,
        failure: .center,
        placeholder: .center
    )
)

Nuke.loadImage(with: url, options: options, into: imageView)
```

To make all image views in the app share the same behavior modify `ImageLoadingOptions.shared`.

> If `ImageLoadingOptions` are missing a feature that you need, please use `ImagePipeline` directly. If you think that everyone could benefit from this feature, PRs are welcome.

#### Image Requests

Each request is represented by an `ImageRequest` struct. A request can be created either with `URL` or `URLRequest`.

```swift
var request = ImageRequest(url: url)
// var request = ImageRequest(urlRequest: URLRequest(url: url))

// Change memory cache policy:
request.memoryCacheOptions.isWriteAllowed = false

// Update the request priority:
request.priority = .high

Nuke.loadImage(with: request, into: imageView)
```

#### Process an Image

Resize an image using special `ImageRequest` initializer.

```swift
// Target size is in pixels.
ImageRequest(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
```

Perform custom tranformation using `processed(key:closure:)` method. Her's how to create a circular avatar using [Toucan](https://github.com/gavinbunney/Toucan).

```swift
ImageRequest(url: url).process(key: "circularAvatar") {
    Toucan(image: $0).maskWithEllipse().image
}
```

All those APIs are built on top of `ImageProcessing` protocol which you can also use to implement custom processors. Keep in mind that `ImageProcessing` also requires `Equatable` conformance which helps Nuke identify images in memory cache.

> See [Core Image Integration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Core%20Image%20Integration%20Guide.md) for info about using Core Image with Nuke

# Advanced Usage

#### Image Pipeline

Use `ImagePipeline` directly to load images without a view.

```swift
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { _, completed, total in
        print("progress updated")
    },
    completion: { response, error in
        print("task completed")
    }
)
```

Tasks can be used to monitor download progress, cancel the requests, and dynamically update download priority.

```swift
task.cancel()
task.setPriority(.high)
```

> To learn more about the `ImagePipeline` [see the dedicated section](#h_design).

#### Configuring Image Pipeline

Apart from using a shared `ImagePipeline` instance, you can create your own.

```swift
let pipeline = ImagePipeline {
    $0.dataLoader = ...
    $0.dataLoadingQueue = ...
    $0.imageCache = ...
    ...
}

// When you're done you can make the pipeline a shared one:
ImagePipeline.shared = pipeline
```

#### Memory Cache

Default Nuke's `ImagePipeline` has two cache layers.

First, there is a memory cache for storing processed images ready for display. You can get a direct access to this cache:

```swift
// Configure cache
ImageCache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
ImageCache.shared.countLimit = 100
ImageCache.shared.ttl = 120 // Invalidate image after 120 sec

// Read and write images
let request = ImageRequest(url: url)
ImageCache.shared[request] = image
let image = ImageCache.shared[request]

// Clear cache
ImageCache.shared.removeAll()
```

#### HTTP Disk Cache

To store unprocessed image data Nuke uses a `URLCache` instance:

```swift
// Configure cache
DataLoader.sharedUrlCache.diskCapacity = 100
DataLoader.sharedUrlCache.memoryCapacity = 0

// Read and write responses
let request = ImageRequest(url: url)
let _ = DataLoader.sharedUrlCache.cachedResponse(for: request.urlRequest)
DataLoader.sharedUrlCache.removeCachedResponse(for: request.urlRequest)

// Clear cache
DataLoader.sharedUrlCache.removeAllCachedResponses()
```

#### Aggressive Disk Cache

A custom LRU disk cache can be used for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). You can enable it using pipeline's configuration.

```swift
$0.dataCache = try! DataCache(name: "com.myapp.datacache")
```

If you enable aggressive disk cache, make sure that you also disable native URL cache (see `DataLoader`), or you might end up storing the same image data twice.

> `DataCache` type implements public `DataCaching` protocol which can be used for implementing custom data caches.

#### Prefetching Images

[Prefethcing](https://kean.github.io/post/image-preheating) images in advance reduces the wait time for users. Nuke provides an `ImagePreheater` to do just that:

```swift
let preheater = ImagePreheater()
preheater.startPreheating(with: urls)

// Cancels all of the preheating tasks created for the given requests.
preheater.stopPreheating(with: urls)
```

There are trade-offs, prefetching takes up users's data and puts an extra pressure on CPU and memory. To reduce the CPU and memory usage you have an option to choose only the disk cache as a prefetching destination:

```swift
// The preheater with `.diskCache` destination will skip image data decoding
// entirely to reduce CPU and memory usage. It will still load the image data
// and store it in disk caches to be used later.
let preheater = ImagePreheater(destination: .diskCache)
```

To make sure that the prefetching requests don't interfere with normal requests it's best to reduce their priority.

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. On iOS 10.0 you might want to use new [prefetching APIs](https://developer.apple.com/reference/uikit/uitableviewdatasourceprefetching) provided by iOS instead.

> Check out [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) to see what else you can do to improve performance

#### Progressive Decoding

To use progressive image loading you need a pipeline with progressive decoding enabled.

```swift
let pipeline = ImagePipeline {
    $0.isProgressiveDecodingEnabled = true
}
```

And that's it, you can start observing images as they are produced by the pipeline. The progress handler also works as a progressive image handler.

```swift
let imageView = UIImageView()
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { response, _, _ in
        imageView.image = response?.image
    },
    completion: { response, _ in
        imageView.image = response?.image
    }
)
```

> See "Progressive Decoding" demo to see progressive JPEG in practice.

#### Animated Images

Nuke extends `UIImage` with `animatedImageData` property. If you enable it by setting `ImagePipeline.Configuration.isAnimatedImageDataEnabled` to `true` the pipeline will start attaching original image data to the animated images (built-in decoder only supports GIFs for now).

> `ImageCache` takes  `animatedImageData` into account when computing the cost of cached items. `ImagePipeline` doesn't apply processors to the images with animated data.

There is no built-in way to render those images, but there are two integrations available: [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin) and [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) which are both fast and efficient.

> `GIF` is not the most efficient format for transferring and displaying animated images. The current best practice is to [use short videos instead of GIFs](https://developers.google.com/web/fundamentals/performance/optimizing-content-efficiency/replace-animated-gifs-with-video/) (e.g. `MP4`, `WebM`). There is a PoC available in the demo project which uses Nuke to load, cache and display an `MP4` video.

#### WebP

WebP support is provided by [Nuke WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) built by [Ryo Kosuge](https://github.com/ryokosuge). Please follow the intructions from the repo to install it.

#### RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables many common use cases:

- [Going from low to high resolution](https://github.com/kean/RxNuke#going-from-low-to-high-resolution)
- [Loading the first available image](https://github.com/kean/RxNuke#loading-the-first-available-image)
- [Showing stale image while validating it](https://github.com/kean/RxNuke#showing-stale-image-while-validating-it)
- [Load multiple images, display all at once](https://github.com/kean/RxNuke#load-multiple-images-display-all-at-once)
- [Auto retry on failures](https://github.com/kean/RxNuke#auto-retry)
- And [more...](https://github.com/kean/RxNuke#use-cases)

Here's an example of how easy it is to load go flow log to high resolution:

```swift
let pipeline = ImagePipeline.shared
Observable.concat(pipeline.loadImage(with: lowResUrl).orEmpty,
                  pipeline.loadImage(with: highResUtl).orEmpty)
    .subscribe(onNext: { imageView.image = $0 })
    .disposed(by: disposeBag)
```

<a name="h_design"></a>
# Image Pipeline

Nuke's image pipeline consists of roughly five stages which can be customized using the following protocols:

|Protocol|Description|
|--------|-----------|
|`DataLoading`|Download (or return cached) image data|
|`DataCaching`|Custom data cache|
|`ImageDecoding`|Convert data into image objects|
|`ImageProcessing`|Apply image transformations|
|`ImageCaching`|Store image into memory cache|

### Default Image Pipeline

The default image pipeline configuration looks like this:

```swift
ImagePipeline {
    // Shared image cache with a `sizeLimit` equal to ~20% of available RAM.
    $0.imageCache = ImageCache.shared

    // Data loader with a `URLSessionConfiguration.default` but with a
    // custom shared URLCache instance:
    //
    // public static let sharedUrlCache = URLCache(
    //     memoryCapacity: 0,
    //     diskCapacity: 150 * 1024 * 1024, // 150 MB
    //     diskPath: "com.github.kean.Nuke.Cache"
    //  )
    $0.dataLoader = DataLoader()

    // Custom disk cache is disabled by default, the native URL cache used
    // by a `DataLoader` is used instead.
    $0.dataCache = nil

    // Each stage is executed on a dedicated queue with has its own limits.
    $0.dataLoadingQueue.maxConcurrentOperationCount = 6
    $0.imageDecodingQueue.maxConcurrentOperationCount = 1
    $0.imageProcessingQueue.maxConcurrentOperationCount = 2

    // Combine the requests for the same original image into one.
    $0.isDeduplicationEnabled = true

    // Progressive decoding is a resource intensive feature so it is
    // disabled by default.
    $0.isProgressiveDecodingEnabled = false
}
```

### Image Pipeline Overview

Here's what happens when you call `Nuke.loadImage(with: url, into: imageView` method.

First, Nuke synchronously checks if the image is available in the memory cache (`pipeline.configuration.imageCache`). If it's not, Nuke calls `pipeline.loadImage(with: request)` method. The pipeline also checks if the image is available in its memory cache, and if not, starts loading it.

Before starting to load image data, the pipeline also checks whether there are any existing outstanding requests for the same image. If it finds one, no new requests are created.

By default, the data is loaded using [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) with a custom [`URLCache`](https://developer.apple.com/reference/foundation/urlcache) instance (see configuration above). The `URLCache` supports on-disk caching but it requires HTTP cache to be enabled.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more.

When the data is loaded the pipeline decodes the data (creates `UIImage` object from `Data`). Then it applies a default image processor - `ImageDecompressor` - to force data decompression in a background. The processed image is then stored in the memory cache and returned in the completion closure.

> When you create `UIImage` object form data, the data doesn't get decoded immediately. It's decoded the first time it's used - for example, when you display the image in an image view. Decoding is a resource-intensive operation, if you do it on the main thread you might see dropped frames, especially for image formats like JPEG.
>
> To prevent decoding happening on the main thread, Nuke perform it in a background for you. But for even better performance it's recommended to downsample the images. To do so create a request with a target view size:
>
>     ImageRequest(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
>
> **Warning:** target size is in pixels!
>
> See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

### Data Loading and Caching

A built-in `DataLoader` class implements `DataLoading` protocol and uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using a [`URLCache`](https://developer.apple.com/reference/foundation/urlcache) instance, which by default is initialized with a memory capacity of 0 MB (Nuke stores images in memory, not image data) and a disk capacity of 150 MB.

The `URLSession` class natively supports the `data`, `file`, `ftp`, `http`, and `https` URL schemes. Image pipeline can be used with any of those schemes as well.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about image caching

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) guide to learn how to use a custom data loader or cache

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of those workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

### Memory Cache

Processed images which are ready to be displayed are stored in a fast in-memory cache (`ImageCache`). It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a limit which prevents it from using more than ~20% of available RAM. As a good citizen, `ImageCache` automatically evicts images on memory warnings and removes most of the images when the application enters background.

### Resumable Downloads

If the data task is terminated (either because of a failure or a cancelation) and the image was partially loaded, the next load will resume where it was left off. 

Resumable downloads require server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`). The resumable downloads are enabled by default.

> By default resumable data is stored in an efficient memory cache. Future versions might include more customization.

### Request Dedupication

By default `ImagePipeline` combines the requests for the same image (but can be different processors) into the same task. The task's priority is set to the highest priority of registered requests and gets updated when requests are added or removed to the task. The task only gets canceled when all the registered requests are.

> Deduplication can be disabled using `ImagePipeline.Configuration`.

<a name="h_performance"></a>
# Performance

Performance is one of the key differentiating factors for Nuke.

The framework is tuned to do as little work on the main thread as possible. It uses multiple optimizations techniques to achieve that: reducing number of allocations, reducing dynamic dispatch, backing some structs by reference typed storage to reduce ARC overhead, etc.

Nuke is fully asynchronous and works great under stress. `ImagePipeline` schedules each of its stages on a dedicated queue. Each queue limits the number of concurrent tasks, respect request priorities even when moving between queue, and cancels the work as soon as possible. Under certain loads, `ImagePipeline` will also rate limit the requests to prevent trashing of the underlying systems.

Another important performance characteristic is memory usage. Nuke uses a custom memory cache with [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm. It has a limit which prevents it from using more than ~20% of available RAM. As a good citizen, `ImageCache` automatically evicts images on memory warnings and removes most of the images when the application enters background.

### Performance Metrics

When optimizing performance, it's important to measure. Nuke collects detailed performance metrics during the execution of each image task:

```swift
ImagePipeline.shared.didFinishCollectingMetrics = { task, metrics in
    print(metrics)
}
```

![timeline](https://user-images.githubusercontent.com/1567433/39193766-8dfd81b2-47dc-11e8-86b3-f3f69dc73d3a.png)

```
(lldb) po metrics

Task Information {
    Task ID - 1
    Duration - 22:35:16.123 – 22:35:16.475 (0.352s)
    Was canceled - false
    Is Memory Cache Hit - false
    Was Subscribed To Existing Session - false
}
Session Information {
    Session ID - 1
    Total Duration - 0.351s
    Was Canceled - false
}
Timeline {
    22:35:16.124 – 22:35:16.475 (0.351s) - Total
    ------------------------------------
    nil – nil (nil)                      - Check Disk Cache
    22:35:16.131 – 22:35:16.410 (0.278s) - Load Data
    22:35:16.410 – 22:35:16.468 (0.057s) - Decode
    22:35:16.469 – 22:35:16.474 (0.005s) - Process
}
Resumable Data {
    Was Resumed - nil
    Resumable Data Count - nil
    Server Confirmed Resume - nil
}
```

<a name="h_plugins"></a>
# Extensions

There are a variety extensions available for Nuke some of which are built by the community.

|Name|Description|
|--|--|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples of common use cases solved by Rx|
|[**Alamofire**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire) and combine the power of both frameworks|
|[**WebP**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **[Community]** [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**Gifu**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|


<a name="h_contribute"></a>
# Contribution

[Nuke's roadmap](https://trello.com/b/Us4rHryT/nuke) is managed in Trello and is publically available.

If you'd like to contribute, please feel free to create a PR.

<a name="h_requirements"></a>
# Requirements

| Nuke                 | Swift                     | Xcode                | Platforms                                           |
|------------------    |-----------------------    |------------------    |-------------------------------------------------    |
| Nuke 7.6             | Swift 4.2 – 5.0           | Xcode 10.1 – 10.2     | iOS 10.0 / watchOS 3.0 / macOS 10.12 / tvOS 10.0      |
| Nuke 7.2 – 7.5.2     | Swift 4.0 – 4.2     | Xcode 9.2 – 10.1     |  iOS 9.0 / watchOS 2.0 / macOS 10.10 / tvOS 9.0     | 

# License

Nuke is available under the MIT license. See the LICENSE file for more info.
