import Foundation
import Combine

/// JSON-backed store of one-way word-level substitutions.
///
/// Each entry is a single direction: `source → target` for a specific
/// `LayoutPair`. To get reverse behavior, add a second entry for the
/// opposite pair (UI offers a "Save both ways" checkbox for convenience).
///
/// File: `~/Library/Application Support/EzSwitch/word_mappings.json`
final class WordMapperStore: ObservableObject {
    static let shared = WordMapperStore()

    /// Top-level key is `pairKey` ("from|to"), value is a `source → target`
    /// dictionary scoped to that direction.
    @Published private(set) var mappings: [String: [String: String]] = [:]

    /// Optional per-word modifier metadata (`source → Modifier`).
    @Published private(set) var modifiers: [String: [String: KeyboardLayoutUtility.Modifier]] = [:]

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.ezswitch.wordmapperstore", qos: .userInitiated)
    private let modifiersDefaultsKey = "wordMappingsModifiers"

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// All source→target entries for a given language pair (merges both
    /// `from|to` and `to|from` so the user has one unified list for the pair).
    func entries(for pair: LayoutPair) -> [String: String] {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        var merged = mappings[inverseKey] ?? [:]
        if let direct = mappings[pair.key] {
            for (k, v) in direct {
                merged[k] = v
            }
        }
        return merged
    }

    /// Return the modifier for a given word in a language pair.
    /// Defaults to `.shift` if the source or target contains uppercase characters.
    func modifier(for source: String, target: String? = nil, pair: LayoutPair) -> KeyboardLayoutUtility.Modifier {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        if let mod = modifiers[pair.key]?[source] ?? modifiers[inverseKey]?[source] {
            return mod
        }
        let resolvedTarget = target ?? entries(for: pair)[source] ?? ""
        if source.contains(where: { $0.isUppercase }) || resolvedTarget.contains(where: { $0.isUppercase }) {
            return .shift
        }
        return .none
    }

    /// Save a substitution for a language pair. Overwrites any previous value
    /// for the same `source` in either direction of the pair.
    func set(source: String, target: String, modifier: KeyboardLayoutUtility.Modifier? = nil, for pair: LayoutPair) {
        guard !source.isEmpty, !target.isEmpty else { return }
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        if var inverseDict = mappings[inverseKey], inverseDict.removeValue(forKey: source) != nil {
            if inverseDict.isEmpty {
                mappings.removeValue(forKey: inverseKey)
            } else {
                mappings[inverseKey] = inverseDict
            }
        }
        var current = mappings[pair.key] ?? [:]
        current[source] = target
        mappings[pair.key] = current

        if let modifier = modifier {
            modifiers[inverseKey]?.removeValue(forKey: source)
            var currentMods = modifiers[pair.key] ?? [:]
            currentMods[source] = modifier
            modifiers[pair.key] = currentMods
        }
        persist()
    }

    /// Remove a single substitution from either direction of the language pair.
    func remove(source: String, for pair: LayoutPair) {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        var changed = false

        if var current = mappings[pair.key], current.removeValue(forKey: source) != nil {
            if current.isEmpty {
                mappings.removeValue(forKey: pair.key)
            } else {
                mappings[pair.key] = current
            }
            changed = true
        }

        if var inverse = mappings[inverseKey], inverse.removeValue(forKey: source) != nil {
            if inverse.isEmpty {
                mappings.removeValue(forKey: inverseKey)
            } else {
                mappings[inverseKey] = inverse
            }
            changed = true
        }

        modifiers[pair.key]?.removeValue(forKey: source)
        modifiers[inverseKey]?.removeValue(forKey: source)

        if changed {
            persist()
        }
    }

    /// Remove all substitutions for a language pair (both directions).
    func removeAll(for pair: LayoutPair) {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        let removedDirect = mappings.removeValue(forKey: pair.key) != nil
        let removedInverse = mappings.removeValue(forKey: inverseKey) != nil
        modifiers.removeValue(forKey: pair.key)
        modifiers.removeValue(forKey: inverseKey)
        if removedDirect || removedInverse {
            persist()
        }
    }

    /// Look up a substitution for a typed word in a given direction.
    /// Checks the active direction first, then the inverse direction (in case
    /// a mapping like "lf → да" was saved under the primary pair key), and
    /// finally falls back across all stored pairs.
    func findMatch(word: String, pair: LayoutPair) -> WordMatchResult? {
        if let direct = WordMatcher.findMatch(word: word, in: entries(for: pair)) {
            return direct
        }
        let inversePair = LayoutPair(from: pair.to, to: pair.from)
        if let inverse = WordMatcher.findMatch(word: word, in: entries(for: inversePair)) {
            return inverse
        }
        for (key, dict) in mappings where key != pair.key && key != inversePair.key {
            if let fallback = WordMatcher.findMatch(word: word, in: dict) {
                return fallback
            }
        }
        return nil
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = support.appendingPathComponent(Constants.FilePath.appSupportFolder, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(Constants.FilePath.wordMappingsFile)
    }

    private func loadFromDisk() {
        if let modData = UserDefaults.standard.data(forKey: modifiersDefaultsKey),
           let decodedMods = try? JSONDecoder().decode([String: [String: KeyboardLayoutUtility.Modifier]].self, from: modData) {
            modifiers = decodedMods
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("🗂 [WordMapperStore] No word mappings file found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            mappings = try decoder.decode([String: [String: String]].self, from: data)
            let total = mappings.values.reduce(0) { $0 + $1.count }
            print("🗂 [WordMapperStore] Loaded \(total) word mapping(s) from disk")
        } catch {
            print("⚠️ [WordMapperStore] Failed to load word mappings: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let snapshot = mappings
        let modsSnapshot = modifiers
        if let modData = try? JSONEncoder().encode(modsSnapshot) {
            UserDefaults.standard.set(modData, forKey: modifiersDefaultsKey)
        }
        queue.async { [weak self, snapshot] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: self.fileURL, options: .atomic)
                let total = snapshot.values.reduce(0) { $0 + $1.count }
                print("🗂 [WordMapperStore] Saved \(total) word mapping(s) to disk")
            } catch {
                print("⚠️ [WordMapperStore] Failed to save word mappings: \(error.localizedDescription)")
            }
        }
    }
}

private extension LayoutPair {
    /// Stable string key for dictionary storage.
    var key: String { Constants.WordSub.pairKey(from: from, to: to) }
}
