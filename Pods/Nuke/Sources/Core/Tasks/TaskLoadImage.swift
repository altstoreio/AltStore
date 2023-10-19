// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
///
/// Performs all the quick cache lookups and also manages image processing.
/// The coalesing for image processing is implemented on demand (extends the
/// scenarios in which coalescing can kick in).
final class TaskLoadImage: ImagePipelineTask<ImageResponse> {
    override func start() {
        // Memory cache lookup
        if let image = pipeline.cache[request] {
            let response = ImageResponse(container: image, cacheType: .memory)
            send(value: response, isCompleted: !image.isPreview)
            if !image.isPreview {
                return // Already got the result!
            }
        }

        // Disk cache lookup
        if let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline),
           !request.options.contains(.disableDiskCacheReads) {
            operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
                self?.getCachedData(dataCache: dataCache)
            }
            return
        }

        // Fetch image
        fetchImage()
    }

    // MARK: Disk Cache Lookup

    private func getCachedData(dataCache: DataCaching) {
        let data = signpost(log, "ReadCachedProcessedImageData") {
            pipeline.cache.cachedData(for: request)
        }
        async {
            if let data = data {
                self.didReceiveCachedData(data)
            } else {
                self.fetchImage()
            }
        }
    }

    private func didReceiveCachedData(_ data: Data) {
        guard !isDisposed else { return }

        let context = ImageDecodingContext(request: request, data: data, isCompleted: true, urlResponse: nil)
        guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            // This shouldn't happen in practice unless encoder/decoder pair
            // for data cache is misconfigured.
            return fetchImage()
        }

        let decode = {
            signpost(log, "DecodeCachedProcessedImageData") {
                decoder.decode(data, urlResponse: nil, isCompleted: true, cacheType: .disk)
            }
        }
        if !decoder.isAsynchronous {
            didDecodeCachedData(decode())
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self = self else { return }
                let response = decode()
                self.async {
                    self.didDecodeCachedData(response)
                }
            }
        }
    }

    private func didDecodeCachedData(_ response: ImageResponse?) {
        if let response = response {
            decompressImage(response, isCompleted: true, isFromDiskCache: true)
        } else {
            fetchImage()
        }
    }

    // MARK: Fetch Image

    private func fetchImage() {
        // Memory cache lookup for intermediate images.
        // For example, for processors ["p1", "p2"], check only ["p1"].
        // Then apply the remaining processors.
        //
        // We are not performing data cache lookup for intermediate requests
        // for now (because it's not free), but maybe adding an option would be worth it.
        // You can emulate this behavior by manually creating intermediate requests.
        if request.processors.count > 1 {
            var processors = request.processors
            var remaining: [ImageProcessing] = []
            if let last = processors.popLast() {
                remaining.append(last)
            }
            while !processors.isEmpty {
                if let image = pipeline.cache[request.withProcessors(processors)] {
                    let response = ImageResponse(container: image, cacheType: .memory)
                    process(response, isCompleted: !image.isPreview, processors: remaining)
                    if !image.isPreview {
                        return  // Nothing left to do, just apply the processors
                    } else {
                        break
                    }
                }
                if let last = processors.popLast() {
                    remaining.append(last)
                }
            }
        }

        let processors: [ImageProcessing] = request.processors.reversed()
        // The only remaining choice is to fetch the image
        if request.options.contains(.returnCacheDataDontLoad) {
            // Same error that URLSession produces when .returnCacheDataDontLoad
            // is specified and the data is no found in the cache.
            let error = NSError(domain: URLError.errorDomain, code: URLError.resourceUnavailable.rawValue, userInfo: nil)
            send(error: .dataLoadingFailed(error))
        } else if request.processors.isEmpty {
            dependency = pipeline.makeTaskFetchDecodedImage(for: request).subscribe(self) { [weak self] in
                self?.process($0, isCompleted: $1, processors: processors)
            }
        } else {
            let request = self.request.withProcessors([])
            dependency = pipeline.makeTaskLoadImage(for: request).subscribe(self) { [weak self] in
                self?.process($0, isCompleted: $1, processors: processors)
            }
        }
    }

    // MARK: Processing

    /// - parameter processors: Remaining processors to by applied
    private func process(_ response: ImageResponse, isCompleted: Bool, processors: [ImageProcessing]) {
        guard !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil) else {
            self.decompressImage(response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            dependency2?.unsubscribe() // Cancel any potential pending progressive processing tasks
        } else if dependency2 != nil {
            return  // Back pressure - already processing another progressive image
        }

        _process(response, isCompleted: isCompleted, processors: processors)
    }

    /// - parameter processors: Remaining processors to by applied
    private func _process(_ response: ImageResponse, isCompleted: Bool, processors: [ImageProcessing]) {
        guard let processor = processors.last else {
            self.decompressImage(response, isCompleted: isCompleted)
            return
        }

        let key = ImageProcessingKey(image: response, processor: processor)
        dependency2 = pipeline.makeTaskProcessImage(key: key, process: { [request] in
            let context = ImageProcessingContext(request: request, response: response, isFinal: isCompleted)
            return signpost(log, "ProcessImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                response.map { processor.process($0, context: context) }
            }
        }).subscribe(priority: priority) { [weak self] event in
            guard let self = self else { return }
            if event.isCompleted {
                self.dependency2 = nil
            }
            switch event {
            case .value(let response, _):
                self._process(response, isCompleted: isCompleted, processors: processors.dropLast())
            case .error:
                if isCompleted {
                    self.send(error: .processingFailed(processor))
                }
            case .progress:
                break // Do nothing (Not reported by OperationTask)
            }
        }
    }

    // MARK: Decompression

    #if os(macOS)
    private func decompressImage(_ response: ImageResponse, isCompleted: Bool, isFromDiskCache: Bool = false) {
        storeImageInCaches(response, isFromDiskCache: isFromDiskCache)
        send(value: response, isCompleted: isCompleted) // There is no decompression on macOS
    }
    #else
    private func decompressImage(_ response: ImageResponse, isCompleted: Bool, isFromDiskCache: Bool = false) {
        guard isDecompressionNeeded(for: response) else {
            storeImageInCaches(response, isFromDiskCache: isFromDiskCache)
            send(value: response, isCompleted: isCompleted)
            return
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decompression tasks
        } else if operation != nil {
            return  // Back-pressure: we are receiving data too fast
        }

        guard !isDisposed else { return }

        operation = pipeline.configuration.imageDecompressingQueue.add { [weak self] in
            guard let self = self else { return }

            let response = signpost(log, "DecompressImage", isCompleted ? "FinalImage" : "ProgressiveImage") {
                response.map { $0.map(ImageDecompression.decompress(image:)) } ?? response
            }

            self.async {
                self.storeImageInCaches(response, isFromDiskCache: isFromDiskCache)
                self.send(value: response, isCompleted: isCompleted)
            }
        }
    }

    private func isDecompressionNeeded(for response: ImageResponse) -> Bool {
        return pipeline.configuration.isDecompressionEnabled &&
            ImageDecompression.isDecompressionNeeded(for: response.image) ?? false &&
            !(ImagePipeline.Configuration._isAnimatedImageDataEnabled && response.image._animatedImageData != nil)
    }
    #endif

    // MARK: Caching

    private func storeImageInCaches(_ response: ImageResponse, isFromDiskCache: Bool) {
        guard subscribers.contains(where: { $0 is ImageTask }) else {
            return // Only store for direct requests
        }
        // Memory cache (ImageCaching)
        pipeline.cache[request] = response.container
        // Disk cache (DataCaching)
        if !isFromDiskCache {
            storeImageInDataCache(response)
        }
    }

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard !response.container.isPreview else {
            return
        }
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline), shouldStoreFinalImageInDiskCache() else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = pipeline.delegate.imageEncoder(for: context, pipeline: pipeline)
        let key = pipeline.cache.makeDataCacheKey(for: request)
        pipeline.configuration.imageEncodingQueue.addOperation { [weak pipeline, request] in
            guard let pipeline = pipeline else { return }
            let encodedData = signpost(log, "EncodeImage") {
                encoder.encode(response.container, context: context)
            }
            guard let data = encodedData else { return }
            pipeline.delegate.willCache(data: data, image: response.container, for: request, pipeline: pipeline) {
                guard let data = $0 else { return }
                // Important! Storing directly ignoring `ImageRequest.Options`.
                dataCache.storeData(data, for: key) // This is instant, writes are async
            }
        }
        if pipeline.configuration.debugIsSyncImageEncoding { // Only for debug
            pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        }
    }

    private func shouldStoreFinalImageInDiskCache() -> Bool {
        guard request.url?.isCacheable ?? false else {
            return false
        }
        let policy = pipeline.configuration.dataCachePolicy
        return ((policy == .automatic || policy == .storeAll) && !request.processors.isEmpty) || policy == .storeEncodedImages
    }
}
