import Foundation
import OSLog
import SwiftData

/// 用于测量 ModelContext 操作的性能指标收集器
@MainActor
struct ModelContextPerformanceMetrics {
    private static let signposter = OSSignposter(
        subsystem: "com.gwyy.appcontest2026.medicationadherence",
        category: "Performance"
    )

    private static let logger = Logger(
        subsystem: "com.gwyy.appcontest2026.medicationadherence",
        category: "Performance"
    )

    /// 测量 ModelContext fetch 操作的性能
    static func measureFetch<T>(
        operation: String,
        execute: () throws -> T
    ) rethrows -> T {
        let interval = signposter.beginInterval("modelcontext.fetch", id: signposter.makeSignpostID())
        signposter.emitEvent("fetch.start", "operation=\(operation)")
        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            signposter.endInterval("modelcontext.fetch", interval, "operation=\(operation) duration=\(String(format: "%.3f", duration * 1000))ms")

            if duration > 0.100 {
                logger.warning("ModelContext fetch exceeded 100ms: operation=\(operation, privacy: .public) duration=\(String(format: "%.3f", duration * 1000), privacy: .public)ms")
            }
        }

        return try execute()
    }

    /// 测量 ModelContext save 操作的性能
    static func measureSave(
        operation: String,
        execute: () throws -> Void
    ) rethrows {
        let interval = signposter.beginInterval("modelcontext.save", id: signposter.makeSignpostID())
        signposter.emitEvent("save.start", "operation=\(operation)")
        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            signposter.endInterval("modelcontext.save", interval, "operation=\(operation) duration=\(String(format: "%.3f", duration * 1000))ms")

            if duration > 0.100 {
                logger.warning("ModelContext save exceeded 100ms: operation=\(operation, privacy: .public) duration=\(String(format: "%.3f", duration * 1000), privacy: .public)ms")
            }
        }

        try execute()
    }

    /// 测量 ModelContext delete 操作的性能
    static func measureDelete(
        operation: String,
        execute: () throws -> Void
    ) rethrows {
        let interval = signposter.beginInterval("modelcontext.delete", id: signposter.makeSignpostID())
        signposter.emitEvent("delete.start", "operation=\(operation)")
        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            signposter.endInterval("modelcontext.delete", interval, "operation=\(operation) duration=\(String(format: "%.3f", duration * 1000))ms")

            if duration > 0.100 {
                logger.warning("ModelContext delete exceeded 100ms: operation=\(operation, privacy: .public) duration=\(String(format: "%.3f", duration * 1000), privacy: .public)ms")
            }
        }

        try execute()
    }

    /// 测量通用 ModelContext 操作的性能
    static func measureOperation<T>(
        name: String,
        operation: String,
        execute: () throws -> T
    ) rethrows -> T {
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
        signposter.emitEvent("\(name).start", "operation=\(operation)")
        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            signposter.endInterval(name, interval, "operation=\(operation) duration=\(String(format: "%.3f", duration * 1000))ms")

            if duration > 0.100 {
                logger.warning("ModelContext operation exceeded 100ms: name=\(name, privacy: .public) operation=\(operation, privacy: .public) duration=\(String(format: "%.3f", duration * 1000), privacy: .public)ms")
            }
        }

        return try execute()
    }
}
