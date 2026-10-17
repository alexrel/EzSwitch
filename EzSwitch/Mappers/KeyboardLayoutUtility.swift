import Foundation
import Carbon
import AppKit

/// Utility for working with macOS keyboard layouts via UCKeyTranslate.
/// Provides character lookup by virtual key code and modifier state.
enum KeyboardLayoutUtility {

    // MARK: - Types

    /// Modifier flags for character lookup.
    /// These are the `UCKeyTranslate` modifier masks (UnicodeUtilities.h) —
    /// see `Constants.UCTModifier` for the same bit values. NOTE: these
    /// are NOT the same as Carbon event modifier masks (`Constants.ModifierMask`)
    /// — the UCKeyTranslate API uses a separate, smaller bitfield.
    /// Enum raw values must be literals, so we repeat the bits here.
    enum Modifier: UInt32, Codable {
        case none = 0
        case shift = 0x02          // 1 << 1
        case option = 0x08         // 1 << 3
        case shiftOption = 0x0A    // shift | option
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

    /// Get input source by localized name
    static func inputSource(named name: String) -> TISInputSource? {
        let sources = availableInputSources()
        for source in sources {
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let localizedName = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
                if localizedName == name {
                    return source
                }
            }
        }
        return nil
    }

    /// Get localized name of an input source
    static func localizedName(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// Get all enabled keyboard layout names
    static func enabledLayoutNames() -> [String] {
        let sources = availableInputSources()
        var names: [String] = []
        for source in sources {
            if let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                let enabledCF = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
                if !CFBooleanGetValue(enabledCF) { continue }
            }
            if let name = localizedName(of: source), !name.isEmpty {
                names.append(name)
            }
        }
        return names
    }

    /// Look up a character for a given key code in a specific layout with modifiers
    static func character(
        forKeyCode keyCode: UInt16,
        modifier: Modifier,
        layoutName: String
    ) -> Character? {
        guard let source = inputSource(named: layoutName) else {
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
    static func characterTable(forLayoutNamed name: String) -> [CharacterEntry] {
        guard let source = inputSource(named: name) else {
            return []
        }
        return characterTable(for: source)
    }

    /// Reverse-lookup: find the first key code in the current (or named)
    /// layout that produces `character`. Prefers base (no modifier) over
    /// Shift. Used by `KeyboardManager` to type replacement characters.
    static func reverseLookup(
        character: Character,
        inLayoutNamed name: String? = nil
    ) -> CharacterEntry? {
        let source: TISInputSource
        if let name = name {
            guard let s = inputSource(named: name) else { return nil }
            source = s
        } else {
            guard let s = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                return nil
            }
            source = s
        }
        let table = characterTable(for: source)
        if let base = table.first(where: { $0.modifier == .none && $0.character == character }) {
            return base
        }
        if let shifted = table.first(where: { $0.modifier == .shift && $0.character == character }) {
            return shifted
        }
        return nil
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

    /// Build a forward mapping (from source layout to target layout)
    /// by matching key code + modifier combinations.
    ///
    /// Only `none` and `shift` modifier states are used. This excludes the
    /// hundreds of exotic Option+letter symbols (e.g. `Ω`, `æ`, `·`, `€`)
    /// that would otherwise pollute the mapping. Users who want to remap
    /// specific Option-symbols can do so manually in the editor.
    static func buildMapping(fromLayout sourceName: String, toLayout targetName: String) -> [String: String] {
        // Use only base and Shift — the characters people actually type.
        let sourceEntries = characterTable(forLayoutNamed: sourceName)
            .filter { $0.modifier == .none || $0.modifier == .shift }
        let targetEntries = characterTable(forLayoutNamed: targetName)
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
