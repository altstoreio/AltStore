// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

public struct ImageTaskMetrics: CustomDebugStringConvertible {
    public let taskId: Int
    public internal(set) var wasCancelled: Bool = false
    public internal(set) var session: SessionMetrics?

    public let startDate: Date
    public internal(set) var processStartDate: Date?
    public internal(set) var processEndDate: Date?
    public internal(set) var endDate: Date? // failed or completed
    public var totalDuration: TimeInterval? {
        guard let endDate = endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }

    /// Returns `true` is the task wasn't the one that initiated image loading.
    public internal(set) var wasSubscibedToExistingSession: Bool = false
    public internal(set) var isMemoryCacheHit: Bool = false

    init(taskId: Int, startDate: Date) {
        self.taskId = taskId; self.startDate = startDate
    }

    public var debugDescription: String {
        var printer = Printer()
        printer.section(title: "Task Information") {
            $0.value("Task ID", taskId)
            $0.timeline("Duration", startDate, endDate, isReversed: false)
            $0.timeline("Process", processStartDate, processEndDate)
            $0.value("Was Cancelled", wasCancelled)
            $0.value("Is Memory Cache Hit", isMemoryCacheHit)
            $0.value("Was Subscribed To Existing Image Loading Session", wasSubscibedToExistingSession)
        }
        printer.section(title: "Image Loading Session") {
            $0.string(session.map({ $0.debugDescription }) ?? "nil")
        }
        return printer.output()
    }

    // Download session metrics. One more more tasks can share the same
    // session metrics.
    public final class SessionMetrics: CustomDebugStringConvertible {
        /// - important: Data loading might start prior to `timeResumed` if the task gets
        /// coalesced with another task.
        public let sessionId: Int
        public internal(set) var wasCancelled: Bool = false

        // MARK: - Timeline

        public let startDate = Date()

        public internal(set) var checkDiskCacheStartDate: Date?
        public internal(set) var checkDiskCacheEndDate: Date?

        public internal(set) var loadDataStartDate: Date?
        public internal(set) var loadDataEndDate: Date?

        public internal(set) var decodeStartDate: Date?
        public internal(set) var decodeEndDate: Date?

        @available(*, deprecated, message: "Please use the same property on `ImageTaskMetrics` instead.")
        public internal(set) var processStartDate: Date?

        @available(*, deprecated, message: "Please use the same property on `ImageTaskMetrics` instead.")
        public internal(set) var processEndDate: Date?

        public internal(set) var endDate: Date? // failed or completed

        public var totalDuration: TimeInterval? {
            guard let endDate = endDate else { return nil }
            return endDate.timeIntervalSince(startDate)
        }

        // MARK: - Resumable Data

        public internal(set) var wasResumed: Bool?
        public internal(set) var resumedDataCount: Int?
        public internal(set) var serverConfirmedResume: Bool?

        public internal(set) var downloadedDataCount: Int?
        public var totalDownloadedDataCount: Int? {
            guard let downloaded = self.downloadedDataCount else { return nil }
            return downloaded + (resumedDataCount ?? 0)
        }

        init(sessionId: Int) { self.sessionId = sessionId }

        public var debugDescription: String {
            var printer = Printer()
            printer.section(title: "Session Information") {
                $0.value("Session ID", sessionId)
                $0.value("Total Duration", Printer.duration(totalDuration))
                $0.value("Was Cancelled", wasCancelled)
            }
            printer.section(title: "Timeline") {
                $0.timeline("Total", startDate, endDate)
                $0.line(String(repeating: "-", count: 36))
                $0.timeline("Check Disk Cache", checkDiskCacheStartDate, checkDiskCacheEndDate)
                $0.timeline("Load Data", loadDataStartDate, loadDataEndDate)
                $0.timeline("Decode", decodeStartDate, decodeEndDate)
            }
            printer.section(title: "Resumable Data") {
                $0.value("Was Resumed", wasResumed)
                $0.value("Resumable Data Count", resumedDataCount)
                $0.value("Server Confirmed Resume", serverConfirmedResume)
            }
            return printer.output()
        }
    }
}
