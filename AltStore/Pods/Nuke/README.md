<br/>

<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="205">

# Image Loading System

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<img src="https://github.com/kean/Nuke/workflows/Nuke%20CI/badge.svg">
</p>

Nuke ILS provides an efficient way to download and display images in your app. It's easy to learn and use thanks to a clear and concise API. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

Despite the number of features, the framework is lean and compiles in under 2 seconds[¹](#footnote-1). Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for [performance](https://kean.blog/post/nuke-9).

> **Fast LRU memory and disk cache** · **SwiftUI** · **Smart background decompression** · **Image processing** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Prefetching** · **Rate limiting** · **Progressive JPEG, HEIF, WebP, SVG, GIF** · **Alamofire** · **Combine** · **Reactive extensions**

## Sponsors
[![Stream](https://i.imgur.com/oU7XYkk.png)](https://getstream.io/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship)

Nuke is proudly sponsored by [Stream](https://getstream.io/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship), the leading provider in enterprise grade [Feed](https://getstream.io/activity-feeds/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship) & [Chat](https://getstream.io/chat/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship) APIs. [Try the iOS Chat Tutorial](https://getstream.io/tutorials/ios-chat/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship).

[![Keygen](https://camo.githubusercontent.com/3cb2f34584248f3eb8a7ee4ead0d3d04950f4f62b9797c53316535b9b40d2036/68747470733a2f2f73696e647265736f726875732e636f6d2f6173736574732f7468616e6b732f6b657967656e2d6c6f676f2e737667)](https://keygen.sh/?ref=kean)

Nuke is also sponsored by [Keygen](https://keygen.sh/?ref=kean), a dead-simple software licensing and distribution API built for developers, by developers.

## Documentation

Nuke is easy to learn and use thanks to beautiful [**Nuke Docs**](https://kean.blog/nuke/guides/welcome). Make sure to also check out [**Nuke Demo**](https://github.com/kean/NukeDemo).

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/10.0.0/Documentation/Migrations). Switching from another framework? Use a [**Switching Guide**](https://github.com/kean/Nuke/tree/master/Documentation/Switch).

<a href="https://kean.blog/nuke/guides/welcome">
<img src="https://user-images.githubusercontent.com/1567433/114312077-59259b80-9abf-11eb-93f9-29fb87eb025a.png">
</a>

Nuke documentation is also available for [download](https://t.co/r03Svmcv8B?amp=1) as an Xcode 13 documentation archive compiled using DocC. 

<a name="h_plugins"></a>
## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**NukeUI**](https://github.com/kean/NukeUI)|Lazy image loading for SwiftUI|
|[**NukeBuilder**](https://github.com/kean/NukeBuilder)|A fun and convenient way to use Nuke|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**Gifu Plugin**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage Plugin**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|
|[**Xamarin NuGet**](https://github.com/roubachof/Xamarin.Forms.Nuke)| **Community**. Makes it possible to use Nuke from Xamarin|

<a name="h_contribute"></a>
## Contribution

[Nuke's roadmap](https://trello.com/b/Us4rHryT/nuke) is managed in Trello and is publicly available.

<a name="h_requirements"></a>
## Minimum Requirements

| Nuke          | Swift           | Xcode           | Platforms                                         |
|---------------|-----------------|-----------------|---------------------------------------------------|
| Nuke 10.0      | Swift 5.3       | Xcode 12.0      | iOS 11.0 / watchOS 4.0 / macOS 10.13 / tvOS 11.0  |
| Nuke 9.0      | Swift 5.1       | Xcode 11.0      | iOS 11.0 / watchOS 4.0 / macOS 10.13 / tvOS 11.0  |

See [Installation Guide](https://kean.blog/nuke/guides/installation) for information about the older versions.

## License

Nuke is available under the MIT license. See the LICENSE file for more info.

----

> <a name="footnote-1">¹</a> Measured on MacBook Pro 14" 2021 (10-core M1 Pro)
