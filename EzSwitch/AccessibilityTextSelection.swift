import ApplicationServices

/// Fallback for modal text fields whose responder chain ignores Copy/Paste shortcuts.
struct AccessibilityTextSelection {
    let element: AXUIElement
    let text: String
    let range: CFRange

    static func focused() -> AccessibilityTextSelection? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                           kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var selectedText: CFTypeRef?
        var selectedRange: CFTypeRef?
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
              let text = selectedText as? String, !text.isEmpty,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
              let selectedRange, CFGetTypeID(selectedRange) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(selectedRange as! AXValue, .cfRange, &range), range.length > 0 else { return nil }
        return AccessibilityTextSelection(element: element, text: text, range: range)
    }

    private static var manualAccessibilityPIDs: Set<pid_t> = []

    /// Selection length in the app's focused field, or nil when the app does not expose it.
    /// Call from one serial queue only.
    static func focusedSelectionLength(pid: pid_t) -> Int? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        if result != .success, manualAccessibilityPIDs.insert(pid).inserted {
            // Electron builds its accessibility tree only when asked.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            usleep(50_000)
            result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        }
        var range: CFTypeRef?
        var value = CFRange()
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range, CFGetTypeID(range) == AXValueGetTypeID(),
              AXValueGetValue(range as! AXValue, .cfRange, &value) else { return nil }
        return value.length
    }

    func replace(with replacement: String) -> Bool {
        guard let current = Self.focused(), matches(current) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                           replacement as CFString) == .success
    }

    func matches(_ other: Self) -> Bool {
        CFEqual(element, other.element) && text == other.text &&
            range.location == other.range.location && range.length == other.range.length
    }
}
