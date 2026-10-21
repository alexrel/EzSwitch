import Foundation
import Carbon

/// Centralized constants — timings, key codes, modifier masks, default
/// values, and storage keys. Keeps magic numbers and strings out of the
/// call sites so they can be tweaked and audited in one place.
enum Constants {

    // MARK: - Stored Hotkey Modifier Masks
    // Persisted bit values used by Hotkey. Convert them explicitly to CGEventFlags;
    // they are not interchangeable with UCKeyTranslate or Carbon modifier masks.
    enum ModifierMask {
        static let command: UInt32 = 0x100
        static let shift:   UInt32 = 0x200
        static let option:  UInt32 = 0x40
        static let control: UInt32 = 0x1000
    }

    // MARK: - UCKeyTranslate Modifier Masks
    // Separate, smaller bitfield used by `UCKeyTranslate`
    // (UnicodeUtilities.h). Not interchangeable with the stored hotkey
    // masks above.
    enum UCTModifier {
        static let none:   UInt32 = 0
        static let shift:  UInt32 = 0x02   // 1 << 1
        static let option: UInt32 = 0x08   // 1 << 3
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

        // Capture (Cmd+C round-trip via pasteboard)
        static let captureTimeoutSec:          TimeInterval = 0.35
        static let capturePollStepUs:          UInt32 = 3_000
        static let captureSelectionTimeoutSec: TimeInterval = 0.2
        static let captureKeyDelayUs:          UInt32 = 10_000

        // Paste (Cmd+V) — used by word sub auto-replace and hotkey training
        static let pasteCmdVDeferSec:     TimeInterval = 0.1   // if hotkey modifiers still held
        static let pasteRestoreDelaySec:  TimeInterval = 0.4

        // Layout switch scheduled shortly after a word replacement so the
        // paste lands in the target app before the input source changes.
        static let layoutSwitchDelaySec:  TimeInterval = 0.08

        // Clipboard restore after a transform (TextTransformer)
        static let clipboardRestoreDelay: TimeInterval = 0.25

        // The preset editor saves on every keystroke; coalesce those into a
        // single disk write once typing pauses.
        static let persistDebounceSec:    TimeInterval = 0.4

        // How long a multi-step transform cycle stays "live": transforming
        // again within this window advances to the next layout in the plan.
        static let cycleExpirySec:        TimeInterval = 2.5

        // UI: delay before moving first-responder into a sheet's source field,
        // giving the window a beat to finish presenting.
        static let sheetFocusDelaySec:    TimeInterval = 0.1

        // UI: delay before the launch-time Accessibility check, so the alert
        // does not compete with the status bar finishing its setup.
        static let accessibilityCheckDelaySec: TimeInterval = 0.8
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
        /// Sentinel for "no layout chosen". Never a real input source id.
        static let noneLanguage  = "None"
        /// Default switcher pair, as stable input source ids — not localized
        /// names, which change with the system language (see `LayoutRegistry`).
        static let leftLayoutID  = "com.apple.keylayout.RussianWin"
        static let rightLayoutID = "com.apple.keylayout.ABC"
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
        /// UserDefaults keys for the layout switcher pair.
        ///
        /// The *values* are stable input source ids (`com.apple.keylayout.*`).
        /// Older versions used `leftCommandLanguage`/`rightCommandLanguage`.
        /// These new keys do not migrate those legacy values.
        static let leftCommandLayout        = "leftCommandLayout"
        static let rightCommandLayout       = "rightCommandLayout"
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
        static let wordMappingsSwitchLayouts  = "wordMappingsSwitchLayouts"
        /// Last layout pair used in the mapper window.
        static let lastMapperFromLayout       = "lastMapperFromLayout"
        static let lastMapperToLayout         = "lastMapperToLayout"
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

    // MARK: - Clipboard Marker
    enum ClipboardMarker {
        static let prefix = "__EZ_"
    }

    // MARK: - Links
    enum Link {
        static let repository = URL(string: "https://github.com/alexrel/EzSwitch")!
        /// Same repo, without the scheme — for inline display text.
        static let repositoryDisplay = "github.com/alexrel/EzSwitch"
    }
}
