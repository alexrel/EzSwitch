import Foundation
import OSLog

/// Centralised logging.
///
/// This replaces the `print()` calls that used to go to a stdout nobody ever
/// watches — a menu-bar app has no console attached when it is launched from
/// Finder, so those lines were invisible exactly when a user reported a
/// problem. Unified logging is readable after the fact:
///
///     log stream --predicate 'category == "transform"' --debug
///
/// Two things are deliberate here, keep them that way when adding a line:
///
/// 1. **Level.** `.error` is reserved for genuine failures a user would
///    report: persistence failed, the event tap could not be created, a
///    required permission is missing. Everything else — pipeline steps,
///    configuration summaries, "fell back to the other method" — is
///    `.debug`. There is no `.info`/`.default` chatter: successful steps
///    logging by default is exactly the noise this replaces.
///
/// 2. **Privacy.** Interpolated strings are redacted as `<private>` unless
///    marked otherwise, which would render a trace useless. Since every
///    value logged here sits either at `.debug` (opt-in — it is not collected
///    until you ask for it) or in an `.error` that carries no user content,
///    values are marked `.public` on purpose: the level is the gate, not the
///    redaction. If something genuinely sensitive appears, keep it out of the
///    message instead of leaning on redaction.
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
