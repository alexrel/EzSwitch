import Foundation
import Carbon

/// Centralized constants — timings, key codes, modifier masks, default
/// values, and storage keys. Keeps magic numbers and strings out of the
/// call sites so they can be tweaked and audited in one place.
enum Constants {

    // MARK: - Carbon / HIToolbox Modifier Masks
    // Same bit values as `shiftKey` / `cmdKey` / `optionKey` / `controlKey`
    // in HIToolbox/Events.h. Used by `Hotkey` to encode/decode modifier
    // sets, and by the keyboard event monitor to translate `CGEventFlags`.
    enum ModifierMask {
        static let command: UInt32 = 0x100
        static let shift:   UInt32 = 0x200
        static let option:  UInt32 = 0x40
        static let control: UInt32 = 0x1000

        /// All four modifier bits as a single mask — handy for
        /// `flags.intersection(.modifiers)`.
        static let all: UInt32 = command | shift | option | control
    }

    // MARK: - UCKeyTranslate Modifier Masks
    // Separate, smaller bitfield used by `UCKeyTranslate`
    // (UnicodeUtilities.h). Not interchangeable with the HIToolbox
    // masks above.
    enum UCTModifier {
        static let none:        UInt32 = 0
        static let shift:       UInt32 = 0x02   // 1 << 1
        static let option:      UInt32 = 0x08   // 1 << 3
        static let shiftOption: UInt32 = 0x0A
    }

    // MARK: - Virtual Key Codes
    enum KeyCode {
        // Modifier keys
        static let leftShift:  Int = 56
        static let rightShift: Int = 60
        static let leftOption: Int = 58
        static let rightOption: Int = 61
        static let leftCmd:    Int = 55
        static let rightCmd:   Int = 54

        // Common editing & navigation keys
        static let delete:     Int = 51         // kVK_Delete (backspace)
        static let forwardDelete: Int = 117     // kVK_ForwardDelete
        static let escape:     Int = 53         // kVK_Escape
        static let tab:        Int = 48         // kVK_Tab
        static let returnKey:  Int = 36         // kVK_Return
        static let space:      Int = 49         // kVK_Space
        static let c:          Int = kVK_ANSI_C
        static let v:          Int = kVK_ANSI_V
        static let leftArrow:  Int = 0x7B       // 123
        static let rightArrow: Int = 0x7C       // 124
        static let downArrow:  Int = 0x7D       // 125
        static let upArrow:    Int = 0x7E       // 126
        static let home:       Int = 0x73       // 115
        static let end:        Int = 0x77       // 119
        static let pageUp:     Int = 0x74       // 116
        static let pageDown:   Int = 0x79       // 121
    }

    // MARK: - Timings
    enum Timing {
        // Double-tap / hold detection
        static let doubleTapThreshold: TimeInterval = 0.25
        static let commandMaxHold:      TimeInterval = 0.35

        // Simulated key-event delays (microseconds)
        static let keyDownUpDelayUs:     UInt32 = 2_000
        static let keySequenceDelayUs:   UInt32 = 15_000
        static let pasteSettleUs:        UInt32 = 20_000
        static let backspaceDelayUs:     UInt32 = 2_000
        static let betweenCharsDelayUs:  UInt32 = 3_000
        static let layoutSwitchSettleUs: UInt32 = 20_000

        // Capture (Cmd+C round-trip via pasteboard)
        static let captureTimeoutSec:          TimeInterval = 0.35
        static let capturePollStepSec:         TimeInterval = 0.05
        static let capturePollStepUs:          UInt32 = 3_000
        static let captureSelectionTimeoutSec: TimeInterval = 0.2
        static let captureInitialDelayUs:      UInt32 = 10_000
        static let captureKeyDelayUs:          UInt32 = 10_000

        // Paste (Cmd+V) — used by word sub auto-replace and hotkey training
        static let pasteCmdVDeferSec:     TimeInterval = 0.1   // if hotkey modifiers still held
        static let pasteRestoreDelaySec:  TimeInterval = 0.25

        // Clipboard restore after a transform (TextTransformer)
        static let clipboardRestoreDelay: TimeInterval = 0.12
    }

    // MARK: - Word Sub
    enum WordSub {
        /// Minimum typed-word length that triggers an auto-replace.
        /// Set to 2 so 2-letter words (e.g. "lf" → "да") and 3+ letter words ("пше" → "git") both work.
        /// Change to 3 if you only want 3+ letter words to trigger auto-replace.
        static let minAutoReplaceLength = 2

        static let pairKeySeparator = "|"

        static func pairKey(from: String, to: String) -> String {
            "\(from)\(pairKeySeparator)\(to)"
        }
    }

    // MARK: - Default Settings
    enum Default {
        static let noneLanguage  = "None"
        static let leftLanguage  = "Russian – PC"
        static let rightLanguage = "ABC"
        static let switchModifierRaw    = "cmd"
        static let transformKeyTypeRaw  = "bothOption"
        static let enableTransformKey         = true
        static let suppressTransformKey       = false
        static let switchLayoutAfterTransform = true
        static let commandSwitchEnabled       = true
        static let enableWordSubstitution     = true
        static let launchAtLogin              = true

        // Default "remember word" hotkey: ⌘⇧M
        static let rememberHotkeyKeyCode:   UInt16 = 46   // kVK_ANSI_M
        static let rememberHotkeyModifiers: UInt32 = ModifierMask.command | ModifierMask.shift
    }

    // MARK: - UserDefaults Keys
    enum DefaultsKey {
        static let leftCommandLanguage        = "leftCommandLanguage"
        static let rightCommandLanguage       = "rightCommandLanguage"
        static let enableTransformKey         = "enableTransformKey"
        static let transformKeyType           = "transformKeyType"
        static let suppressTransformKey       = "suppressTransformKey"
        static let switchLayoutAfterTransform = "switchLayoutAfterTransform"
        static let commandSwitchEnabled       = "commandSwitchEnabled"
        static let launchAtLogin              = "launchAtLogin"
        static let switchModifier             = "switchModifier"
        static let selectedPresetIds          = "selectedPresetIds"
        static let enableWordSubstitution     = "enableWordSubstitution"
        static let wordRememberHotkey         = "wordRememberHotkey"
    }

    // MARK: - File Paths
    enum FilePath {
        static let appSupportFolder = "EzSwitch"
        static let presetsFile      = "presets.json"
        static let wordMappingsFile = "word_mappings.json"
    }

    // MARK: - Word Selection (TextTransformer)
    enum WordSelection {
        /// Safety cap on successive Option+Shift+Left presses used to
        /// extend a selection to the start of the word.
        static let maxIterations = 10
        /// Treat selections longer than this as "probably the whole line"
        /// and reject them.
        static let maxWordLength = 50
    }

    // MARK: - Unicode
    enum Unicode {
        /// Cyrillic block (U+0400..U+04FF).
        static let cyrillicLower: UInt32 = 0x0400
        static let cyrillicUpper: UInt32 = 0x04FF
    }

    // MARK: - Clipboard Marker
    enum ClipboardMarker {
        static let prefix = "__EZ_"
    }
}
