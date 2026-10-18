import Foundation

/// Represents a pair of keyboard layouts (source → target)
struct LayoutPair: Hashable, Codable {
    let from: String
    let to: String

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    /// Compare layout names tolerantly: localized names differ in dash style
    /// (`–` vs `—` vs `-`), letter case and surrounding whitespace.
    /// Never compares against language keywords — any pair of layouts works.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        func normalize(_ name: String) -> String {
            name
                .replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "–", with: "-")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        }
        return normalize(a) == normalize(b)
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

    /// Optional description
    var description: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        fromLayout: String,
        toLayout: String,
        mapping: [String: String] = [:],
        extraMappings: [ExtraMapping] = [],
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fromLayout = fromLayout
        self.toLayout = toLayout
        self.mapping = mapping
        self.extraMappings = extraMappings
        self.description = description
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
