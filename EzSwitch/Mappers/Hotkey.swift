import Foundation
import Carbon

/// A user-configurable keyboard shortcut. Stored as `(keyCode, modifiers)`
/// because both are stable numeric values — survives layout changes and
/// is portable across languages.
struct Hotkey: Codable, Equatable, Hashable {
    /// Virtual key code (e.g. kVK_ANSI_M = 46).
    var keyCode: UInt16
    /// Carbon-style modifier mask. We use the same bits as HIToolbox so
    /// we can compare directly with `CGEventFlags` translated values.
    ///   cmdKey     = 0x100
    ///   shiftKey   = 0x200
    ///   optionKey  = 0x40
    ///   controlKey = 0x1000
    var modifiers: UInt32

    /// Default: ⌘⇧M (keyCode 46, cmd + shift).
    static let `default` = Hotkey(
        keyCode: Constants.Default.rememberHotkeyKeyCode,
        modifiers: Constants.Default.rememberHotkeyModifiers
    )

    /// Empty hotkey (no key assigned).
    static let none = Hotkey(keyCode: 0, modifiers: 0)

    var isSet: Bool { keyCode != 0 || modifiers != 0 }

    /// Human-readable label like "⌘⇧M". Falls back to key code for unknown keys.
    var displayLabel: String {
        displayTokens.joined()
    }

    /// List of individual key labels like `["⌘", "⇧", "M"]` for rendering as separate keycaps.
    var displayTokens: [String] {
        guard isSet else { return ["—"] }
        var parts: [String] = []
        if modifiers & Constants.ModifierMask.command != 0 { parts.append("⌘") }
        if modifiers & Constants.ModifierMask.shift   != 0 { parts.append("⇧") }
        if modifiers & Constants.ModifierMask.option  != 0 { parts.append("⌥") }
        if modifiers & Constants.ModifierMask.control != 0 { parts.append("⌃") }
        parts.append(Hotkey.keyName(for: keyCode))
        return parts
    }

    /// CGEventFlags equivalent of `modifiers` for comparison in event taps.
    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if modifiers & Constants.ModifierMask.command != 0 { f.insert(.maskCommand) }
        if modifiers & Constants.ModifierMask.shift   != 0 { f.insert(.maskShift) }
        if modifiers & Constants.ModifierMask.option  != 0 { f.insert(.maskAlternate) }
        if modifiers & Constants.ModifierMask.control != 0 { f.insert(.maskControl) }
        return f
    }

    /// True if `flags` matches our modifier set (we ignore extra modifiers
    /// the user may be holding — e.g. Caps Lock).
    func matches(flags: CGEventFlags) -> Bool {
        // Required modifiers we expect to be set
        let need: CGEventFlags = cgFlags
        // Mask out the modifier bits we don't care about (caps lock, fn, etc.)
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let clean = flags.intersection(relevant)
        return clean == need
    }

    // MARK: - Codable
    // Stored as `[keyCode, modifiers]` so it serializes compactly.
    init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.keyCode = UInt16(try c.decode(Int.self))
        self.modifiers = UInt32(try c.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(Int(keyCode))
        try c.encode(Int(modifiers))
    }

    // MARK: - Display name lookup
    private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        // Letters
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"; case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"; case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"; case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"; case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        // Digits
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        // Special
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"; case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"; case kVK_DownArrow: return "↓"
        default: return "Key \(keyCode)"
        }
    }
}
