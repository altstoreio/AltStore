// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches original image from the data loader (`DataLoading`) and stores it
/// in the disk cache (`DataCaching`).
final class TaskFetchOriginalImageData: ImagePipelineTask<(Data, URLResponse?)> {
    private var urlResponse: URLResponse?
    private var resumableData: ResumableData?
    private var resumedDataCount: Int64 = 0
    private lazy var data = Data()

    override func start() {
        guard let urlRequest = request.urlRequest else {
            self.send(error: .dataLoadingFailed(URLError(.badURL)))
            return
        }
        
        if let rateLimiter = pipeline.rateLimiter {
            // Rate limiter is synchronized on pipeline's queue. Delayed work is
            // executed asynchronously also on the same queue.
            rateLimiter.execute { [weak self] in
                guard let self = self, !self.isDisposed else {
                    return false
                }
                self.loadData(urlRequest: urlRequest)
                return true
            }
        } else { // Start loading immediately.
            loadData(urlRequest: urlRequest)
        }
    }

    private func loadData(urlRequest: URLRequest) {
        // Wrap data request in an operation to limit the maximum number of
        // concurrent data tasks.
        operation = pipeline.configuration.dataLoadingQueue.add { [weak self] finish in
            guard let self = self else {
                return finish()
            }
            self.async {
                self.loadData(urlRequest: urlRequest, finish: finish)
            }
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadData(urlRequest: URLRequest, finish: @escaping () -> Void) {
        guard !isDisposed else {
            return finish()
        }
        // Read and remove resumable data from cache (we're going to insert it
        // back in the cache if the request fails to complete again).
        var urlRequest = urlRequest
        if pipeline.configuration.isResumableDataEnabled,
           let resumableData = ResumableDataStorage.shared.removeResumableData(for: request, pipeline: pipeline) {
            // Update headers to add "Range" and "If-Range" headers
            resumableData.resume(request: &urlRequest)
            // Save resumable data to be used later (before using it, the pipeline
            // verifies that the server returns "206 Partial Content")
            self.resumableData = resumableData
        }

        signpost(log, self, "LoadImageData", .begin, "URL: \(urlRequest.url?.absoluteString ?? ""), resumable data: \(Formatter.bytes(resumableData?.data.count ?? 0))")

        let dataLoader = pipeline.delegate.dataLoader(for: request, pipeline: pipeline)
        let dataTask = dataLoader.loadData(with: urlRequest, didReceiveData: { [weak self] data, response in
            guard let self = self else { return }
            self.async {
                self.dataTask(didReceiveData: data, response: response)
            }
        }, completion: { [weak self] error in
            finish() // Finish the operation!
            guard let self = self else { return }
            signpost(log, self, "LoadImageData", .end, "Finished with size \(Formatter.bytes(self.data.count))")
            self.async {
                self.dataTaskDidFinish(error: error)
            }
        })

        onCancelled = { [weak self] in
            guard let self = self else { return }

            signpost(log, self, "LoadImageData", .end, "Cancelled")
            dataTask.cancel()
            finish() // Finish the operation!

            self.tryToSaveResumableData()
        }
    }

    private func dataTask(didReceiveData chunk: Data, response: URLResponse) {
        // Check if this is the first response.
        if urlResponse == nil {
            // See if the server confirmed that the resumable data can be used
            if let resumableData = resumableData, ResumableData.isResumedResponse(response) {
                data = resumableData.data
                resumedDataCount = Int64(resumableData.data.count)
                signpost(log, self, "LoadImageData", .event, "Resumed with data \(Formatter.bytes(resumedDataCount))")
            }
            resumableData = nil // Get rid of resumable data
        }

        // Append data and save response
        data.append(chunk)
        urlResponse = response

        let progress = TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)
        send(progress: progress)

        // If the image hasn't been fully loaded yet, give decoder a change
        // to decode the data chunk. In case `expectedContentLength` is `0`,
        // progressive decoding doesn't run.
        guard data.count < response.expectedContentLength else { return }

        send(value: (data, response))
    }

    private func dataTaskDidFinish(error: Swift.Error?) {
        if let error = error {
            tryToSaveResumableData()
            send(error: .dataLoadingFailed(error))
            return
        }

        // Sanity check, should never happen in practice
        guard !data.isEmpty else {
            send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return
        }

        // Store in data cache
        if let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline), shouldStoreDataInDiskCache() {
            let key = pipeline.cache.makeDataCacheKey(for: request)
            pipeline.delegate.willCache(data: data, image: nil, for: request, pipeline: pipeline) {
                guard let data = $0 else { return }
                // Important! Storing directly ignoring `ImageRequest.Options`.
                dataCache.storeData(data, for: key)
            }
        }

        send(value: (data, urlResponse), isCompleted: true)
    }

    private func shouldStoreDataInDiskCache() -> Bool {
        guard request.url?.isCacheable ?? false else {
            return false
        }
        let policy = pipeline.configuration.dataCachePolicy
        guard imageTasks.contains(where: { !$0.request.options.contains(.disableDiskCacheWrites) }) else {
            return false
        }
        return policy == .storeOriginalData || policy == .storeAll || (policy == .automatic && imageTasks.contains { $0.request.processors.isEmpty })
    }

    private func tryToSaveResumableData() {
        // Try to save resumable data in case the task was cancelled
        // (`URLError.cancelled`) or failed to complete with other error.
        if pipeline.configuration.isResumableDataEnabled,
           let response = urlResponse, !data.isEmpty,
           let resumableData = ResumableData(response: response, data: data) {
            ResumableDataStorage.shared.storeResumableData(resumableData, for: request, pipeline: pipeline)
        }
    }
}
