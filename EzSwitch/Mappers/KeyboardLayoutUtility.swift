import Foundation
import Carbon
import AppKit

/// Utility for working with macOS keyboard layouts via UCKeyTranslate.
/// Provides character lookup by virtual key code and modifier state.
enum KeyboardLayoutUtility {

    // MARK: - Threading

    /// TIS requires the main thread (it asserts on the main queue internally).
    /// The transform pipeline runs on a background queue to avoid blocking
    /// keystroke delivery, so TIS-backed lookups hop here instead of asserting.
    private static func onMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    // MARK: - Types

    /// Modifier flags for character lookup.
    /// These are the `UCKeyTranslate` modifier masks (UnicodeUtilities.h) —
    /// see `Constants.UCTModifier` for the same bit values. These are separate
    /// from the persisted hotkey masks in `Constants.ModifierMask`.
    /// Enum raw values must be literals, so we repeat the bits here.
    enum Modifier: UInt32, Codable {
        case none = 0
        case shift = 0x02          // 1 << 1
        case option = 0x08         // 1 << 3
        case shiftOption = 0x0A    // shift | option

        /// Human-readable label used in the editor and mapping lists.
        var displayName: String {
            switch self {
            case .none: return String(localized: "No modifier")
            case .shift: return "Shift"
            case .option: return "Option"
            case .shiftOption: return String(localized: "Shift + Option")
            }
        }
    }

    /// Represents a single character in a layout, with metadata
    struct CharacterEntry {
        let keyCode: UInt16
        let modifier: Modifier
        let character: Character
    }

    // MARK: - Public API

    /// Get all available keyboard input sources
    static func availableInputSources() -> [TISInputSource] {
        onMain { availableInputSourcesOnMain() }
    }

    private static func availableInputSourcesOnMain() -> [TISInputSource] {
        let filter: [String: Any] = [
            (kTISPropertyInputSourceCategory as String): (kTISCategoryKeyboardInputSource as String),
            (kTISPropertyInputSourceIsSelectCapable as String): true
        ]
        guard let rawList = TISCreateInputSourceList(filter as CFDictionary, false) else {
            return []
        }
        let list = rawList.takeRetainedValue() as NSArray
        return (list as? [TISInputSource]) ?? []
    }

    /// Stable input source id, e.g. `com.apple.keylayout.RussianWin`.
    ///
    /// Unlike `kTISPropertyLocalizedName` this does not change when the system
    /// language changes, which is why EzSwitch persists ids and never names.
    static func inputSourceID(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.isEmpty ? nil : id
    }

    /// Whether the source is enabled and can actually be selected.
    static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return true }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    /// Input source for a stored layout value.
    ///
    /// Resolved by stable id. Values saved before ids were introduced still
    /// hold a localized name, so those fall back to a tolerant name match —
    /// best effort, and only as long as the language is unchanged.
    static func inputSource(forLayout value: String) -> TISInputSource? {
        let sources = availableInputSources()

        if let byID = sources.first(where: { inputSourceID(of: $0) == value }) {
            return byID
        }
        guard !value.isEmpty else { return nil }
        return sources.first { source in
            guard let name = localizedName(of: source) else { return false }
            return LayoutPair.namesMatch(name, value)
        }
    }

    /// Get localized name of an input source
    static func localizedName(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Look up a character for a given key code in a specific layout with modifiers
    ///
    /// - Parameter layout: stable layout id. Values saved before ids were
    ///   introduced may resolve by their name in the current locale.
    static func character(
        forKeyCode keyCode: UInt16,
        modifier: Modifier,
        layout: String
    ) -> Character? {
        guard let source = inputSource(forLayout: layout) else {
            return nil
        }
        return character(forKeyCode: keyCode, modifier: modifier, inputSource: source)
    }

    /// Look up a character using TISInputSource directly
    static func character(
        forKeyCode keyCode: UInt16,
        modifier: Modifier,
        inputSource source: TISInputSource
    ) -> Character? {
        guard let keyboardDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let keyboardData = Unmanaged<CFData>.fromOpaque(keyboardDataPtr).takeUnretainedValue() as Data
        return character(forKeyCode: keyCode, modifier: modifier, keyboardLayoutData: keyboardData)
    }

    /// Look up a character with raw keyboard layout data
    static func character(
        forKeyCode keyCode: UInt16,
        modifier: Modifier,
        keyboardLayoutData: Data
    ) -> Character? {
        let keyboardLayout = keyboardLayoutData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) -> UnsafePointer<UCKeyboardLayout>? in
            let bound = rawPtr.bindMemory(to: UCKeyboardLayout.self)
            return bound.baseAddress
        }
        guard let layout = keyboardLayout else {
            return nil
        }

        var deadKeyState: UInt32 = 0
        let maxStringLength = 4
        var stringBuffer = [UniChar](repeating: 0, count: maxStringLength)
        var actualStringLength: Int = 0

        let status = stringBuffer.withUnsafeMutableBufferPointer { ptr -> OSStatus in
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifier.rawValue,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxStringLength,
                &actualStringLength,
                ptr.baseAddress
            )
        }

        guard status == noErr, actualStringLength > 0 else {
            return nil
        }

        let unicodeString = String(utf16CodeUnits: stringBuffer, count: actualStringLength)
        return unicodeString.first
    }

    /// Extract complete character table for a layout (all key codes × all modifiers)
    ///
    /// - Parameter layout: stable ID, or a legacy name resolvable in the current locale.
    static func characterTable(forLayout layout: String) -> [CharacterEntry] {
        onMain { characterTableOnMain(forLayout: layout) }
    }

    private static func characterTableOnMain(forLayout layout: String) -> [CharacterEntry] {
        guard let source = inputSource(forLayout: layout) else {
            return []
        }
        return characterTable(for: source)
    }

    /// Extract complete character table from a TISInputSource
    static func characterTable(for source: TISInputSource) -> [CharacterEntry] {
        var entries: [CharacterEntry] = []
        let modifiers: [Modifier] = [.none, .shift, .option, .shiftOption]

        // Cover all reasonable key codes (0..<128)
        for keyCode: UInt16 in 0..<128 {
            for modifier in modifiers {
                if let char = character(forKeyCode: keyCode, modifier: modifier, inputSource: source) {
                    // Skip dead keys (often shown as empty or specific characters)
                    if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char == " " {
                        entries.append(CharacterEntry(keyCode: keyCode, modifier: modifier, character: char))
                    }
                }
            }
        }
        return entries
    }

    /// Translate `text` from one layout to another using the system layouts
    /// themselves (not the saved presets) and picking the direction that best
    /// matches the characters in `text`.
    static func autoTranslate(_ text: String, from: String, to: String) -> String {
        let forwardMap = buildMapping(fromLayout: from, toLayout: to)
        let reverseMap = buildMapping(fromLayout: to, toLayout: from)

        var forwardHits = 0
        var reverseHits = 0
        for ch in text {
            let s = String(ch)
            let inForward = forwardMap[s] != nil && forwardMap[s] != s
            let inReverse = reverseMap[s] != nil && reverseMap[s] != s
            if inForward && !inReverse { forwardHits += 1 }
            if inReverse && !inForward { reverseHits += 1 }
        }

        let activeMap = reverseHits > forwardHits ? reverseMap : forwardMap
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            let s = String(ch)
            result.append(activeMap[s] ?? s)
        }
        return result
    }

    /// Build a forward mapping (from source layout to target layout)
    /// by matching key code + modifier combinations.
    ///
    /// Only `none` and `shift` modifier states are used. This excludes the
    /// hundreds of exotic Option+letter symbols (e.g. `Ω`, `æ`, `·`, `€`)
    /// that would otherwise pollute the mapping. Users who want to remap
    /// specific Option-symbols can do so manually in the editor.
    ///
    /// - Parameters:
    ///   - sourceLayout: stable layout id of the layout being mapped from.
    ///   - targetLayout: stable layout id of the layout being mapped to.
    static func buildMapping(fromLayout sourceLayout: String, toLayout targetLayout: String) -> [String: String] {
        // Use only base and Shift — the characters people actually type.
        let sourceEntries = characterTable(forLayout: sourceLayout)
            .filter { $0.modifier == .none || $0.modifier == .shift }
        let targetEntries = characterTable(forLayout: targetLayout)
            .filter { $0.modifier == .none || $0.modifier == .shift }

        // Index target entries by (keyCode, modifier)
        var targetIndex: [String: Character] = [:]
        for entry in targetEntries {
            let key = "\(entry.keyCode)_\(entry.modifier.rawValue)"
            targetIndex[key] = entry.character
        }

        var mapping: [String: String] = [:]
        for entry in sourceEntries {
            let key = "\(entry.keyCode)_\(entry.modifier.rawValue)"
            if let targetChar = targetIndex[key] {
                let sourceStr = String(entry.character)
                let targetStr = String(targetChar)
                if !mapping.keys.contains(sourceStr) {
                    mapping[sourceStr] = targetStr
                }
            }
        }
        return mapping
    }
}
