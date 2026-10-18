import Cocoa

/// Thin wrapper around synthetic keyboard events.
///
/// Every call site used to build the same `CGEventSource` → down → sleep →
/// up → post sequence by hand (with slightly different flags handling).
/// Centralising it keeps the timing and the event-tap choice consistent:
/// `.cgAnnotatedSessionEventTap` sends the event to the focused app without
/// re-entering our own HID event tap.
enum CGEventSynthesizer {

    /// Press and release `keyCode`, optionally holding `flags` for both halves.
    /// `delayUs` defaults to the standard key down/up gap.
    static func press(
        _ keyCode: UInt16,
        flags: CGEventFlags = [],
        delayUs: UInt32 = Constants.Timing.keyDownUpDelayUs
    ) {
        let source = CGEventSource(stateID: .combinedSessionState)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cgAnnotatedSessionEventTap)

        usleep(delayUs)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Convenience overload for the `Int` key codes kept in `Constants.KeyCode`.
    static func press(
        _ keyCode: Int,
        flags: CGEventFlags = [],
        delayUs: UInt32 = Constants.Timing.keyDownUpDelayUs
    ) {
        press(UInt16(keyCode), flags: flags, delayUs: delayUs)
    }

    /// ⌘ + `keyCode`
    static func pressCommand(_ keyCode: Int, delayUs: UInt32 = Constants.Timing.keyDownUpDelayUs) {
        press(keyCode, flags: .maskCommand, delayUs: delayUs)
    }
}
