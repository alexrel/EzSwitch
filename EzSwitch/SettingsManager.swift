import Foundation
import OSLog
import ServiceManagement
import Combine

/// Key options for text transformation
enum TransformKeyType: String, CaseIterable {
    case doubleLeftShift = "leftShift"
    case doubleRightShift = "rightShift"
    case doubleBothShift = "bothShift"
    case doubleLeftOption = "leftOption"
    case doubleRightOption = "rightOption"
    case doubleBothOption = "bothOption"

    var displayName: String {
        switch self {
        case .doubleLeftShift: return String(localized: "Double Left Shift")
        case .doubleRightShift: return String(localized: "Double Right Shift")
        case .doubleBothShift: return String(localized: "Double Shift (any)")
        case .doubleLeftOption: return String(localized: "Double Left Option")
        case .doubleRightOption: return String(localized: "Double Right Option")
        case .doubleBothOption: return String(localized: "Double Option (any)")
        }
    }

    var shortName: String {
        switch self {
        case .doubleLeftShift: return "⇧ Left"
        case .doubleRightShift: return "⇧ Right"
        case .doubleBothShift: return "⇧⇧"
        case .doubleLeftOption: return "⌥ Left"
        case .doubleRightOption: return "⌥ Right"
        case .doubleBothOption: return "⌥⌥"
        }
    }

    var isShift: Bool {
        switch self {
        case .doubleLeftShift, .doubleRightShift, .doubleBothShift: return true
        default: return false
        }
    }
}

/// Modifier used by the layout-switch feature. Both Left and Right keys always
/// react (one per language), so this only picks the modifier family (⌘ or ⌥).
/// Independent of the transform key, so you can mix & match without conflict
/// (e.g. layout switch on Option, transform on double Shift).
enum SwitchModifier: String, CaseIterable {
    case command = "cmd"
    case option  = "opt"

    var displayName: String {
        switch self {
        case .command: return String(localized: "⌘  Command")
        case .option:  return String(localized: "⌥  Option")
        }
    }

    /// Whether the modifier is Command (true) or Option (false)
    var isCommand: Bool {
        switch self {
        case .command: return true
        case .option:  return false
        }
    }

    /// Left key code
    var leftKeyCode: Int { isCommand ? Constants.KeyCode.leftCmd : Constants.KeyCode.leftOption }

    /// Right key code
    var rightKeyCode: Int { isCommand ? Constants.KeyCode.rightCmd : Constants.KeyCode.rightOption }

    /// Both sides always react (each side maps to its own language).
    var tracksLeft: Bool  { true }
    var tracksRight: Bool { true }
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    @Published var leftCommandLanguage: String {
        didSet {
            defaults.set(leftCommandLanguage, forKey: Constants.DefaultsKey.leftCommandLanguage)
        }
    }

    @Published var rightCommandLanguage: String {
        didSet {
            defaults.set(rightCommandLanguage, forKey: Constants.DefaultsKey.rightCommandLanguage)
        }
    }

    /// Which modifier is used for layout switching (independent of transform key).
    /// Default keeps the previous behaviour (Left Command / Right Command).
    @Published var switchModifier: SwitchModifier {
        didSet {
            defaults.set(switchModifier.rawValue, forKey: Constants.DefaultsKey.switchModifier)
        }
    }

    @Published var enableTransformKey: Bool {
        didSet {
            defaults.set(enableTransformKey, forKey: Constants.DefaultsKey.enableTransformKey)
            refreshKeyboardMonitoring()
        }
    }

    @Published var transformKeyType: TransformKeyType {
        didSet {
            defaults.set(transformKeyType.rawValue, forKey: Constants.DefaultsKey.transformKeyType)
        }
    }

    /// Suppress event (for PHPStorm etc. where double Shift opens Search Everywhere)
    @Published var suppressTransformKey: Bool {
        didSet {
            defaults.set(suppressTransformKey, forKey: Constants.DefaultsKey.suppressTransformKey)
            refreshKeyboardMonitoring()
        }
    }

    /// Switch layout to result language after transformation
    @Published var switchLayoutAfterTransform: Bool {
        didSet { defaults.set(switchLayoutAfterTransform, forKey: Constants.DefaultsKey.switchLayoutAfterTransform) }
    }

    @Published var commandSwitchEnabled: Bool {
        didSet {
            defaults.set(commandSwitchEnabled, forKey: Constants.DefaultsKey.commandSwitchEnabled)
            refreshKeyboardMonitoring()
        }
    }

    /// Toggles the word-level substitution feature in `KeyboardManager`.
    /// When on, typed words are checked against `WordMapperStore` and
    /// auto-replaced when the user hits a word boundary (space, Enter, punctuation).
    @Published var enableWordSubstitution: Bool {
        didSet {
            defaults.set(enableWordSubstitution, forKey: Constants.DefaultsKey.enableWordSubstitution)
            refreshKeyboardMonitoring()
        }
    }

    /// Global hotkey that saves the currently buffered word to the
    /// word-substitution dictionary. Default: ⌘⇧M.
    @Published var wordRememberHotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(wordRememberHotkey) {
                defaults.set(data, forKey: Constants.DefaultsKey.wordRememberHotkey)
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Constants.DefaultsKey.launchAtLogin)
            setLaunchAtLogin(launchAtLogin)
        }
    }

    /// Stores the selected preset ID per layout pair, so the user can choose
    /// which mapper preset is active for a given pair of languages.
    /// Key = "fromLayout|toLayout", Value = preset.id
    @Published var selectedPresetIds: [String: String] {
        didSet {
            defaults.set(selectedPresetIds, forKey: Constants.DefaultsKey.selectedPresetIds)
        }
    }

    /// Order-independent lookup of the selected preset ID for a language pair.
    /// Returns the same preset ID whether `(a, b)` is `(Russian – PC, ABC)` or `(ABC, Russian – PC)`.
    /// Keys are compared in normalized form (see `LayoutPair.key`), so a pair
    /// saved before a layout rename still resolves.
    func selectedPresetId(for a: String, _ b: String) -> String? {
        let direct = LayoutPair(from: a, to: b).key
        let inverse = LayoutPair(from: b, to: a).key
        return selectedPresetIds[direct] ?? selectedPresetIds[inverse]
    }

    /// Order-independent setter for the selected preset ID of a language pair.
    func setSelectedPresetId(_ id: String?, for a: String, _ b: String) {
        let direct = LayoutPair(from: a, to: b).key
        let inverse = LayoutPair(from: b, to: a).key
        if let id = id {
            selectedPresetIds[direct] = id
            selectedPresetIds[inverse] = id
        } else {
            selectedPresetIds.removeValue(forKey: direct)
            selectedPresetIds.removeValue(forKey: inverse)
        }
    }

    private init() {
        self.leftCommandLanguage = defaults.string(forKey: Constants.DefaultsKey.leftCommandLanguage) ?? Constants.Default.leftLanguage
        self.rightCommandLanguage = defaults.string(forKey: Constants.DefaultsKey.rightCommandLanguage) ?? Constants.Default.rightLanguage
        // Default to Command (Left and Right both react, one per language) so
        // existing users keep their previous behavior.
        self.switchModifier = SwitchModifier(rawValue: defaults.string(forKey: Constants.DefaultsKey.switchModifier) ?? Constants.Default.switchModifierRaw) ?? .command
        self.enableTransformKey = defaults.bool(forKey: Constants.DefaultsKey.enableTransformKey, defaultValue: Constants.Default.enableTransformKey)
        self.transformKeyType = TransformKeyType(rawValue: defaults.string(forKey: Constants.DefaultsKey.transformKeyType) ?? Constants.Default.transformKeyTypeRaw) ?? .doubleBothOption
        self.suppressTransformKey = defaults.bool(forKey: Constants.DefaultsKey.suppressTransformKey, defaultValue: Constants.Default.suppressTransformKey)
        self.switchLayoutAfterTransform = defaults.bool(forKey: Constants.DefaultsKey.switchLayoutAfterTransform, defaultValue: Constants.Default.switchLayoutAfterTransform)
        self.commandSwitchEnabled = defaults.bool(forKey: Constants.DefaultsKey.commandSwitchEnabled, defaultValue: Constants.Default.commandSwitchEnabled)
        self.enableWordSubstitution = defaults.bool(forKey: Constants.DefaultsKey.enableWordSubstitution, defaultValue: Constants.Default.enableWordSubstitution)
        self.launchAtLogin = defaults.bool(forKey: Constants.DefaultsKey.launchAtLogin, defaultValue: Constants.Default.launchAtLogin)
        // Migrate stored pair keys to normalized form (old files used raw
        // layout names, which could differ in dash style / case).
        let rawIds = (defaults.dictionary(forKey: Constants.DefaultsKey.selectedPresetIds) as? [String: String]) ?? [:]
        self.selectedPresetIds = WordMapperStore.migratePairKeys(rawIds) { _, new in new }

        // Hotkey: load from Data (encoded as JSON array)
        if let data = defaults.data(forKey: Constants.DefaultsKey.wordRememberHotkey),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.wordRememberHotkey = hk
        } else {
            self.wordRememberHotkey = .default
        }

        Log.settings.debug("Loaded: left=\(self.leftCommandLanguage, privacy: .public), right=\(self.rightCommandLanguage, privacy: .public), transform=\(self.transformKeyType.displayName, privacy: .public)")

        // Apply launch at login setting (macOS 13+)
        setLaunchAtLogin(self.launchAtLogin)

        // IMPORTANT: keyboard monitoring must work if at least one feature is enabled
        refreshKeyboardMonitoring()
    }

    private func refreshKeyboardMonitoring() {
        // Word sub needs to be able to suppress the hotkey key (e.g. ⌘⇧M) in the
        // target app, so the tap must always run in defaultTap mode when word sub
        // is on — even if the transform key isn't being suppressed.
        let shouldMonitor = commandSwitchEnabled || enableTransformKey || enableWordSubstitution
        let needsSuppression = (enableTransformKey && suppressTransformKey) || enableWordSubstitution

        if shouldMonitor {
            KeyboardManager.shared.startMonitoring(suppressEvents: needsSuppression)
        } else {
            KeyboardManager.shared.stopMonitoring()
        }

        Log.settings.debug("Keyboard monitoring \(shouldMonitor ? "on" : "off", privacy: .public) (commandSwitch=\(self.commandSwitchEnabled ? "on" : "off", privacy: .public), transform=\(self.enableTransformKey ? "on" : "off", privacy: .public), wordSub=\(self.enableWordSubstitution ? "on" : "off", privacy: .public), suppress=\(needsSuppression ? "on" : "off", privacy: .public))")
    }

    // macOS 13+: Launch at login without helper application
    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            Log.permissions.debug("Launch at login \(enable ? "enabled" : "disabled", privacy: .public) (status=\(String(describing: SMAppService.mainApp.status), privacy: .public))")
        } catch {
            Log.permissions.error("Failed to change launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
