import Foundation

/// Represents a pair of keyboard layouts (source → target).
///
/// New `from`/`to` values are input source IDs; older files may contain names.
/// Equality, hashing, and storage keys share normalization for case, dashes,
/// and whitespace. Normalization does not convert localized names into IDs.
struct LayoutPair: Hashable, Codable {
    /// Stable input source id of the source layout.
    let from: String
    /// Stable input source id of the target layout.
    let to: String

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    /// Canonical form of a single layout value.
    ///
    /// Ids are already stable, so this mostly reduces to case folding. The
    /// dash and whitespace folding is kept for values saved before ids were
    /// used, which still hold a localized name — those differ in dash style
    /// (`–` vs `—` vs `-`) and letter case depending on the system language.
    /// This is the one place that defines "same layout".
    static func normalized(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// Compare layout names tolerantly (dash style, case, whitespace).
    /// Never compares against language keywords — any pair of layouts works.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        a == b || normalized(a) == normalized(b)
    }

    static func == (lhs: LayoutPair, rhs: LayoutPair) -> Bool {
        namesMatch(lhs.from, rhs.from) && namesMatch(lhs.to, rhs.to)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Self.normalized(from))
        hasher.combine(Self.normalized(to))
    }
}

extension LayoutPair {
    /// Stable storage key for dictionary persistence (`"from|to"`, normalized).
    /// Old un-normalized keys are migrated on load — see `migrateKey`.
    var key: String {
        Constants.WordSub.pairKey(from: Self.normalized(from), to: Self.normalized(to))
    }

    /// Rebuild a storage key from its `"from|to"` form, normalizing both halves.
    static func migrateKey(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return normalized(key) }
        return Constants.WordSub.pairKey(from: normalized(String(parts[0])), to: normalized(String(parts[1])))
    }
}

/// Represents a saved mapping preset between two keyboard layouts.
/// Maps characters from one layout to another, including shift variants.
struct LayoutMapperPreset: Codable, Identifiable, Equatable {
    /// Unique identifier (UUID string)
    let id: String

    /// Display name for this preset
    var name: String

    /// Generated names are displayed from the current layout labels. Custom
    /// names stay exactly as entered. Nil supports presets saved before this metadata.
    var nameStyle: NameStyle?

    enum NameStyle: String, Codable {
        case custom, automatic, pair
    }

    /// Source layout — stable input source id (e.g. `com.apple.keylayout.RussianWin`).
    /// Legacy presets may still contain a localized name.
    let fromLayout: String

    /// Target layout — stable input source id (e.g. `com.apple.keylayout.ABC`).
    let toLayout: String

    /// Character mapping stored as strings for JSON persistence.
    /// Keys normally contain one character; targets may contain multiple
    /// characters, including emoji or abbreviations.
    var mapping: [String: String]

    /// Explicit character or text overrides, including Option/Shift+Option
    /// characters excluded from the automatically generated key map.
    var extraMappings: [ExtraMapping]

    /// Represents a single custom mapping with an explicit modifier choice.
    /// Stores the modifier as a raw UInt32 in JSON.
    struct ExtraMapping: Codable, Identifiable, Hashable {
        let id: String
        /// Actual source text as typed (e.g. "Ђ" produced with Shift+Option).
        var source: String
        /// Target string (may be multi-byte, e.g. emoji or symbol)
        var target: String
        /// Modifier value as raw UInt32 (KeyboardLayoutUtility.Modifier.rawValue)
        var modifierRaw: UInt32

        /// Computed property to get/set the typed modifier.
        var modifier: KeyboardLayoutUtility.Modifier {
            get { KeyboardLayoutUtility.Modifier(rawValue: modifierRaw) ?? .none }
            set { modifierRaw = newValue.rawValue }
        }

        init(
            id: String = UUID().uuidString,
            source: String,
            target: String,
            modifier: KeyboardLayoutUtility.Modifier = .none
        ) {
            self.id = id
            self.source = source
            self.target = target
            self.modifierRaw = modifier.rawValue
        }
    }

    /// Creation timestamp
    let createdAt: Date

    /// Last modification timestamp
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        fromLayout: String,
        toLayout: String,
        mapping: [String: String] = [:],
        extraMappings: [ExtraMapping] = [],
        nameStyle: NameStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.nameStyle = nameStyle
        self.fromLayout = fromLayout
        self.toLayout = toLayout
        self.mapping = mapping
        self.extraMappings = extraMappings
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// The pair of layouts this preset covers
    var pair: LayoutPair {
        return LayoutPair(from: fromLayout, to: toLayout)
    }

    /// Localized source layout name. `fromLayout`/`toLayout` hold stable
    /// input source ids — resolve them right before showing them.
    var displayFromLayout: String { LayoutRegistry.displayName(forID: fromLayout) }
    /// Localized target layout name. See `displayFromLayout`.
    var displayToLayout: String { LayoutRegistry.displayName(forID: toLayout) }

    var displayName: String {
        switch resolvedNameStyle {
        case .custom: return name
        case .automatic: return String(appLocalized: "\(displayFromLayout) ↔ \(displayToLayout) (auto)")
        case .pair: return String(appLocalized: "\(displayFromLayout) ↔ \(displayToLayout)")
        }
    }

    /// Recognize only exact generated names from older versions, rather than
    /// treating every user name ending in "(auto)" as an automatic title.
    var resolvedNameStyle: NameStyle {
        if let nameStyle { return nameStyle }
        guard name.contains("↔") || name.contains("→") else { return .custom }
        let normalized = LayoutPair.normalized(name)
        for language in ["en", "ru", "uk", "he"] {
            let from = LayoutRegistry.displayName(forID: fromLayout, languageCode: language)
            let to = LayoutRegistry.displayName(forID: toLayout, languageCode: language)
            if normalized == LayoutPair.normalized("\(from) ↔ \(to) (auto)") { return .automatic }
            if normalized == LayoutPair.normalized("\(from) ↔ \(to)") ||
                normalized == LayoutPair.normalized("\(from) → \(to)") { return .pair }
        }
        return .custom
    }

    /// Number of mapped characters
    var mappingCount: Int { mapping.count }

    /// Convert mapping to `[Character: String]` for fast lookup.
    ///
    /// Values are kept as full strings (not just the first character) so
    /// users can map a single source key to a multi-character target —
    /// e.g. `й` → `"QQ"`, emoji, abbreviations, or any Unicode string.
    /// Empty values are skipped (they mean "no mapping" and should not
    /// replace the source character with nothing).
    func characterMapping() -> [Character: String] {
        var result: [Character: String] = [:]
        for (key, value) in mapping {
            guard !value.isEmpty, let k = key.first else { continue }
            result[k] = value
        }
        for extra in extraMappings where extra.source.count == 1 && !extra.target.isEmpty {
            if let source = extra.source.first { result[source] = extra.target }
        }
        return result
    }
}
