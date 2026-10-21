import Foundation
import Combine

/// Resolves strings from a language-specific bundle instead of the main
/// bundle's launch-time language. Changing the selection preserves view state.
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization(language: AppLanguage.stored(in: .standard))

    @Published private(set) var languageCode: String
    private(set) var bundle: Bundle
    private(set) var language: AppLanguage
    private let resourceBundle: Bundle
    private let systemLanguages: () -> [String]
    private var localeObservation: NSObjectProtocol?

    var locale: Locale { Locale(identifier: languageCode) }
    var isRightToLeft: Bool { languageCode == "he" }

    init(
        language: AppLanguage,
        resourceBundle: Bundle = .main,
        systemLanguages: @escaping () -> [String] = AppLocalization.preferredSystemLanguages
    ) {
        self.language = language
        self.resourceBundle = resourceBundle
        self.systemLanguages = systemLanguages
        let code = Self.resolve(language, systemLanguages: systemLanguages())
        languageCode = code
        bundle = Self.bundle(for: code, in: resourceBundle)
        localeObservation = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshSystemLanguage()
        }
    }

    deinit {
        if let localeObservation { NotificationCenter.default.removeObserver(localeObservation) }
    }

    func apply(_ language: AppLanguage) {
        self.language = language
        let code = Self.resolve(language, systemLanguages: systemLanguages())
        guard code != languageCode else { return }
        bundle = Self.bundle(for: code, in: resourceBundle)
        languageCode = code
    }

    func refreshSystemLanguage() {
        if language == .system { apply(.system) }
    }

    func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }

    static func resolve(_ language: AppLanguage, systemLanguages: [String]) -> String {
        guard language == .system else { return language.rawValue }
        let supported = AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
        // Include English last in preferences so unsupported system languages
        // reliably fall back to the app's development language.
        return Bundle.preferredLocalizations(from: supported, forPreferences: systemLanguages + ["en"]).first ?? "en"
    }

    private static func bundle(for code: String, in resources: Bundle) -> Bundle {
        let path = resources.path(forResource: code, ofType: "lproj")
            ?? resources.path(forResource: "en", ofType: "lproj")
        return path.flatMap(Bundle.init(path:)) ?? resources
    }

    private static func preferredSystemLanguages() -> [String] {
        // Locale.preferredLanguages can include this app's AppleLanguages
        // override from launch. Read the global preference for "System Language".
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? [Locale.current.language.languageCode?.identifier ?? "en"]
    }
}

extension String {
    init(appLocalized value: String.LocalizationValue) {
        self = AppLocalization.shared.string(value)
    }
}
