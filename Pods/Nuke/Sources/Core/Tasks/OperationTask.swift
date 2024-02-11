// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A one-shot task for performing a single () -> T function.
final class OperationTask<T>: AsyncTask<T, Swift.Error> {
    private let pipeline: ImagePipeline
    private let queue: OperationQueue
    private let process: () -> T?

    init(_ pipeline: ImagePipeline, _ queue: OperationQueue, _ process: @escaping () -> T?) {
        self.pipeline = pipeline
        self.queue = queue
        self.process = process
    }

    override func start() {
        operation = queue.add { [weak self] in
            guard let self = self else { return }
            let output = self.process()
            self.pipeline.queue.async {
                guard let output = output else {
                    self.send(error: Error())
                    return
                }
                self.send(value: output, isCompleted: true)
            }
        }
    }

    struct Error: Swift.Error {}
}
