// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

final class Operation: Foundation.Operation {
    private let _isExecuting: UnsafeMutablePointer<Int32>
    private let _isFinished: UnsafeMutablePointer<Int32>
    private let isFinishCalled: UnsafeMutablePointer<Int32>

    override var isExecuting: Bool {
        get { _isExecuting.pointee == 1 }
        set {
            guard OSAtomicCompareAndSwap32Barrier(newValue ? 0 : 1, newValue ? 1 : 0, _isExecuting) else {
                return assertionFailure("Invalid state, operation is already (not) executing")
            }
            willChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isExecuting")
        }
    }
    override var isFinished: Bool {
        get { _isFinished.pointee == 1 }
        set {
            guard OSAtomicCompareAndSwap32Barrier(newValue ? 0 : 1, newValue ? 1 : 0, _isFinished) else {
                return assertionFailure("Invalid state, operation is already finished")
            }
            willChangeValue(forKey: "isFinished")
            didChangeValue(forKey: "isFinished")
        }
    }

    typealias Starter = (_ finish: @escaping () -> Void) -> Void
    private let starter: Starter

    deinit {
        self._isExecuting.deallocate()
        self._isFinished.deallocate()
        self.isFinishCalled.deallocate()

        #if TRACK_ALLOCATIONS
        Allocations.decrement("Operation")
        #endif
    }

    init(starter: @escaping Starter) {
        self.starter = starter

        self._isExecuting = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self._isExecuting.initialize(to: 0)

        self._isFinished = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self._isFinished.initialize(to: 0)

        self.isFinishCalled = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self.isFinishCalled.initialize(to: 0)

        #if TRACK_ALLOCATIONS
        Allocations.increment("Operation")
        #endif
    }

    override func start() {
        guard !isCancelled else {
            isFinished = true
            return
        }
        isExecuting = true
        starter { [weak self] in
            self?._finish()
        }
    }

    private func _finish() {
        // Make sure that we ignore if `finish` is called more than once.
        if OSAtomicCompareAndSwap32Barrier(0, 1, isFinishCalled) {
            isExecuting = false
            isFinished = true
        }
    }
}

extension OperationQueue {
    /// Adds simple `BlockOperation`.
    func add(_ closure: @escaping () -> Void) -> BlockOperation {
        let operation = BlockOperation(block: closure)
        addOperation(operation)
        return operation
    }

    /// Adds asynchronous operation (`Nuke.Operation`) with the given starter.
    func add(_ starter: @escaping Operation.Starter) -> Operation {
        let operation = Operation(starter: starter)
        addOperation(operation)
        return operation
    }
}
