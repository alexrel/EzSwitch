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
