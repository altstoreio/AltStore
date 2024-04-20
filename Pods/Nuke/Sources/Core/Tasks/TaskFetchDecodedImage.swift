// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``TaskLoadImageData` and decodes it as it arrives.
final class TaskFetchDecodedImage: ImagePipelineTask<ImageResponse> {
    private var decoder: ImageDecoding?

    override func start() {
        dependency = pipeline.makeTaskFetchOriginalImageData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    /// Receiving data from `OriginalDataTask`.
    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        guard isCompleted || pipeline.configuration.isProgressiveDecodingEnabled else {
            return
        }

        if !isCompleted && operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decoding tasks
        }

        // Sanity check
        guard !data.isEmpty else {
            if isCompleted {
                send(error: .decodingFailed)
            }
            return
        }

        guard let decoder = decoder(data: data, urlResponse: urlResponse, isCompleted: isCompleted) else {
            if isCompleted {
                send(error: .decodingFailed)
            } // Try again when more data is downloaded.
            return
        }

        // Fast-track default decoders, most work is already done during
        // initialization anyway.
        let decode = {
            signpost(log, "DecodeImageData", isCompleted ? "FinalImage" : "ProgressiveImage") {
                decoder.decode(data, urlResponse: urlResponse, isCompleted: isCompleted, cacheType: nil)
            }
        }
        if !decoder.isAsynchronous {
            self.sendResponse(decode(), isCompleted: isCompleted)
        } else {
            operation = pipeline.configuration.imageDecodingQueue.add { [weak self] in
                guard let self = self else { return }

                let response = decode()
                self.async {
                    self.sendResponse(response, isCompleted: isCompleted)
                }
            }
        }
    }

    private func sendResponse(_ response: ImageResponse?, isCompleted: Bool) {
        if let response = response {
            send(value: response, isCompleted: isCompleted)
        } else if isCompleted {
            send(error: .decodingFailed)
        }
    }

    // Lazily creates decoding for task
    private func decoder(data: Data, urlResponse: URLResponse?, isCompleted: Bool) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = self.decoder {
            return decoder
        }
        let context = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
        let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline)
        self.decoder = decoder
        return decoder
    }
}
