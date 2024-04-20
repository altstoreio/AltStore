// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

#if TRACK_ALLOCATIONS
enum Allocations {
    static var allocations = [String: Int]()
    static var total = 0
    static let lock = NSLock()
    static var timer: Timer?

    static let isPrintingEnabled = ProcessInfo.processInfo.environment["NUKE_PRINT_ALL_ALLOCATIONS"] != nil
    static let isTimerEnabled = ProcessInfo.processInfo.environment["NUKE_ALLOCATIONS_PERIODIC_LOG"] != nil

    static func increment(_ name: String) {
        lock.lock()
        defer { lock.unlock() }

        allocations[name, default: 0] += 1
        total += 1

        if isPrintingEnabled {
            debugPrint("Increment \(name): \(allocations[name] ?? 0) Total: \(totalAllocationCount)")
        }

        if isTimerEnabled, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Allocations.printAllocations()
            }
        }
    }

    static var totalAllocationCount: Int {
        allocations.values.reduce(0, +)
    }

    static func decrement(_ name: String) {
        lock.lock()
        defer { lock.unlock() }

        allocations[name, default: 0] -= 1

        let totalAllocationCount = self.totalAllocationCount

        if isPrintingEnabled {
            debugPrint("Decrement \(name): \(allocations[name] ?? 0) Total: \(totalAllocationCount)")
        }

        if totalAllocationCount == 0 {
            _onDeinitAll?()
            _onDeinitAll = nil
        }
    }

    private static var _onDeinitAll: (() -> Void)?

    static func onDeinitAll(_ closure: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        if totalAllocationCount == 0 {
            closure()
        } else {
            _onDeinitAll = closure
        }
    }

    static func printAllocations() {
        lock.lock()
        defer { lock.unlock() }
        let allocations = self.allocations
            .filter { $0.value > 0 }
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " ")
        debugPrint("Current: \(totalAllocationCount) Overall: \(total) \(allocations)")
    }
}
#endif
