// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

#if !os(watchOS)

private extension AssetType {
    var avFileType: AVFileType? {
        switch self {
        case .mp4: return .mp4
        case .m4v: return .m4v
        default: return nil
        }
    }
}

// This class keeps strong pointer to DataAssetResourceLoader
final class AVDataAsset: AVURLAsset {
    private let resourceLoaderDelegate: DataAssetResourceLoader

    init(data: Data, type: AssetType?) {
        self.resourceLoaderDelegate = DataAssetResourceLoader(
            data: data,
            contentType: type?.avFileType?.rawValue ?? AVFileType.mp4.rawValue
        )

        // The URL is irrelevant
        let url = URL(string: "in-memory-data://\(UUID().uuidString)") ?? URL(fileURLWithPath: "/dev/null")
        super.init(url: url, options: nil)

        resourceLoader.setDelegate(resourceLoaderDelegate, queue: .global())
    }
}

// This allows LazyImage to play video from memory.
private final class DataAssetResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let data: Data
    private let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    // MARK: - DataAssetResourceLoader

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = contentType
            contentRequest.contentLength = Int64(data.count)
            contentRequest.isByteRangeAccessSupported = true
        }

        if let dataRequest = loadingRequest.dataRequest {
            if dataRequest.requestsAllDataToEndOfResource {
                dataRequest.respond(with: data[dataRequest.requestedOffset...])
            } else {
                let range = dataRequest.requestedOffset..<(dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                dataRequest.respond(with: data[range])
            }
        }

        loadingRequest.finishLoading()

        return true
    }
}

#endif
