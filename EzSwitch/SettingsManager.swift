import Foundation
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

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    @Published var leftCommandLanguage: String {
        didSet {
            defaults.set(leftCommandLanguage, forKey: Keys.leftCommandLanguage)
            print("💾 Saved left language: \(leftCommandLanguage)")
        }
    }

    @Published var rightCommandLanguage: String {
        didSet {
            defaults.set(rightCommandLanguage, forKey: Keys.rightCommandLanguage)
            print("💾 Saved right language: \(rightCommandLanguage)")
        }
    }

    @Published var enableTransformKey: Bool {
        didSet {
            defaults.set(enableTransformKey, forKey: Keys.enableTransformKey)
            refreshKeyboardMonitoring()
        }
    }

    @Published var transformKeyType: TransformKeyType {
        didSet {
            defaults.set(transformKeyType.rawValue, forKey: Keys.transformKeyType)
            print("💾 Transform key: \(transformKeyType.displayName)")
        }
    }

    /// Suppress event (for PHPStorm etc. where double Shift opens Search Everywhere)
    @Published var suppressTransformKey: Bool {
        didSet {
            defaults.set(suppressTransformKey, forKey: Keys.suppressTransformKey)
            refreshKeyboardMonitoring()
        }
    }

    /// Switch layout to result language after transformation
    @Published var switchLayoutAfterTransform: Bool {
        didSet { defaults.set(switchLayoutAfterTransform, forKey: Keys.switchLayoutAfterTransform) }
    }

    @Published var commandSwitchEnabled: Bool {
        didSet {
            defaults.set(commandSwitchEnabled, forKey: Keys.commandSwitchEnabled)
            refreshKeyboardMonitoring()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            setLaunchAtLogin(launchAtLogin)
        }
    }

    private struct Keys {
        static let leftCommandLanguage = "leftCommandLanguage"
        static let rightCommandLanguage = "rightCommandLanguage"
        static let enableTransformKey = "enableTransformKey"
        static let transformKeyType = "transformKeyType"
        static let suppressTransformKey = "suppressTransformKey"
        static let switchLayoutAfterTransform = "switchLayoutAfterTransform"
        static let commandSwitchEnabled = "commandSwitchEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        self.leftCommandLanguage = defaults.string(forKey: Keys.leftCommandLanguage) ?? "Russian – PC"
        self.rightCommandLanguage = defaults.string(forKey: Keys.rightCommandLanguage) ?? "ABC"
        self.enableTransformKey = defaults.bool(forKey: Keys.enableTransformKey, defaultValue: true)
        self.transformKeyType = TransformKeyType(rawValue: defaults.string(forKey: Keys.transformKeyType) ?? "") ?? .doubleBothOption
        self.suppressTransformKey = defaults.bool(forKey: Keys.suppressTransformKey, defaultValue: false)
        self.switchLayoutAfterTransform = defaults.bool(forKey: Keys.switchLayoutAfterTransform, defaultValue: true)
        self.commandSwitchEnabled = defaults.bool(forKey: Keys.commandSwitchEnabled, defaultValue: true)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin, defaultValue: true)

        print("🔄 Settings loaded: Left=\(leftCommandLanguage), Right=\(rightCommandLanguage), Transform=\(transformKeyType.displayName)")

        // Apply launch at login setting (macOS 13+)
        setLaunchAtLogin(self.launchAtLogin)

        // IMPORTANT: keyboard monitoring must work if at least one feature is enabled
        refreshKeyboardMonitoring()
    }

    private func refreshKeyboardMonitoring() {
        let shouldMonitor = commandSwitchEnabled || enableTransformKey
        let needsSuppression = enableTransformKey && suppressTransformKey

        if shouldMonitor {
            KeyboardManager.shared.startMonitoring(suppressEvents: needsSuppression)
        } else {
            KeyboardManager.shared.stopMonitoring()
        }

        print("⌨️ Keyboard monitoring: \(shouldMonitor ? "ON" : "OFF") (cmd=\(commandSwitchEnabled), transform=\(enableTransformKey), suppress=\(needsSuppression))")
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
            print("✅ Launch at login: \(enable ? "enabled" : "disabled") (status: \(SMAppService.mainApp.status))")
        } catch {
            print("❌ Failed to change Launch at login: \(error.localizedDescription)")
        }
    }

    func save() {
        defaults.set(leftCommandLanguage, forKey: Keys.leftCommandLanguage)
        defaults.set(rightCommandLanguage, forKey: Keys.rightCommandLanguage)
        defaults.set(enableTransformKey, forKey: Keys.enableTransformKey)
        defaults.set(transformKeyType.rawValue, forKey: Keys.transformKeyType)
        defaults.set(suppressTransformKey, forKey: Keys.suppressTransformKey)
        defaults.set(commandSwitchEnabled, forKey: Keys.commandSwitchEnabled)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)

        print("💾 All settings saved")
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
