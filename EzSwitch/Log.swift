import Foundation
import OSLog

/// Unified logging for diagnostics when the app has no attached console.
/// To follow transformation diagnostics:
///
///     log stream --predicate 'category == "transform"' --debug
///
/// Use `.error` for failures such as persistence or event-tap errors; use
/// `.debug` for pipeline tracing and configuration details.
/// Privacy flags apply independently of level: `.public` exposes the value
/// whenever the record is collected, including records at debug level.
enum Log {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ezswitch.EzSwitch"

    /// App lifecycle: launch, status bar, mapper window.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Accessibility / Input Monitoring / login item — the "it does nothing
    /// at all" reports.
    static let permissions = Logger(subsystem: subsystem, category: "permissions")

    /// Loading and saving settings.
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Preset and word-mapping persistence.
    static let store = Logger(subsystem: subsystem, category: "store")

    /// Double-tap transform pipeline: branch choice, planning, cycles.
    static let transform = Logger(subsystem: subsystem, category: "transform")

    /// Word buffer, auto-replace, remember-word hotkey.
    static let words = Logger(subsystem: subsystem, category: "words")
}
