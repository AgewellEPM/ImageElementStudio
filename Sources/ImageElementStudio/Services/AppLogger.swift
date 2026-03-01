import os

/// Centralized structured logging for the app.
///
/// Uses the `os.Logger` API (macOS 14+) for system-native structured logging.
/// Each category gets its own subsystem logger so log messages can be filtered
/// efficiently in Console.app or via `log stream`.
///
/// Usage:
///     AppLogger.info("Pipeline started", category: .pipeline)
///     AppLogger.error("Decode failed: \(err)", category: .api)
enum AppLogger {

    // MARK: - Categories

    enum Category: String, CaseIterable, Sendable {
        case api
        case pipeline
        case build
        case export
        case canvas
        case project
        case security
        case general
    }

    // MARK: - Subsystem

    static let subsystem = "com.imageelementstudio"

    // MARK: - Logger Cache

    /// Thread-safe cache of `Logger` instances keyed by category.
    /// Using `nonisolated(unsafe)` is acceptable here because `Logger` is
    /// value-type-like and the dictionary is only written during first access
    /// per category (effectively idempotent).
    private nonisolated(unsafe) static var loggers: [Category: Logger] = {
        var map: [Category: Logger] = [:]
        for category in Category.allCases {
            map[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        return map
    }()

    // MARK: - Public API

    /// Returns the `Logger` for a given category. Useful when the caller
    /// needs direct access for interpolation or privacy controls.
    static func logger(for category: Category) -> Logger {
        loggers[category]!
    }

    /// Log an informational message.
    static func info(_ message: String, category: Category = .general) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    /// Log a warning-level message (maps to os_log `.default` level,
    /// which is always persisted and visible in Console.app).
    static func warning(_ message: String, category: Category = .general) {
        logger(for: category).warning("\(message, privacy: .public)")
    }

    /// Log an error-level message.
    static func error(_ message: String, category: Category = .general) {
        logger(for: category).error("\(message, privacy: .public)")
    }

    /// Log a debug-level message (only captured during debugging or when
    /// the logging level is explicitly raised).
    static func debug(_ message: String, category: Category = .general) {
        logger(for: category).debug("\(message, privacy: .public)")
    }
}
