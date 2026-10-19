import Foundation

/// Represents a pair of keyboard layouts (source → target)
struct LayoutPair: Hashable, Codable {
    let from: String
    let to: String

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    /// Canonical form of a single layout name: localized names differ in dash
    /// style (`–` vs `—` vs `-`), letter case and surrounding whitespace.
    /// This is the one place that defines "same layout" — equality, hashing
    /// and storage keys all go through it so a pair saved as "Russian – PC|ABC"
    /// is found again no matter which variant the system reports later.
    static func normalized(_ name: String) -> String {
        name
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

    /// Source layout name (e.g., "Russian – PC")
    let fromLayout: String

    /// Target layout name (e.g., "ABC")
    let toLayout: String

    /// Character mapping: source character → target character
    /// Stored as `[String: String]` to support any character including
    /// multi-byte ones. Keys and values are single-character strings
    /// (length 1) in normal usage.
    var mapping: [String: String]

    /// Extra (custom) mappings with modifier support.
    /// Each entry maps a source character + modifier to a target string,
    /// allowing the user to define non-standard key combinations.
    var extraMappings: [ExtraMapping]

    /// Represents a single custom mapping with an explicit modifier choice.
    /// Stores modifier as a raw UInt32 to stay Codable (KeyboardLayoutUtility.Modifier
    /// is not Codable).
    struct ExtraMapping: Codable, Identifiable, Hashable {
        let id: String
        /// Source character (single char, e.g. "п")
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
        extraMappings: [ExtraMapping] = []
    ) {
        self.id = id
        self.name = name
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
        return result
    }
}
