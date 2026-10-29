import Foundation

/// Interface language is independent of keyboard input sources.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru, uk, he, de, fr, es, pl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(appLocalized: "System Language")
        case .en: return "English"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .he: return "עברית"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .pl: return "Polski"
        }
    }

    static func stored(in defaults: UserDefaults) -> AppLanguage {
        if let value = defaults.string(forKey: "interfaceLanguage"), let language = AppLanguage(rawValue: value) {
            return language
        }
        // Respect a language previously chosen for EzSwitch in macOS settings.
        if let bundleID = Bundle.main.bundleIdentifier,
           let languages = defaults.persistentDomain(forName: bundleID)?["AppleLanguages"] as? [String],
           let first = languages.first {
            return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
        }
        return .system
    }

    func save(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: "interfaceLanguage")
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
