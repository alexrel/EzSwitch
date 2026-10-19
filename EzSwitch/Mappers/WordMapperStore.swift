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

    /// Optional per-word flag indicating whether to switch keyboard layout to target language.
    @Published private(set) var switchLayouts: [String: [String: Bool]] = [:]

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.ezswitch.wordmapperstore", qos: .userInitiated)
    private let switchLayoutsDefaultsKey = Constants.DefaultsKey.wordMappingsSwitchLayouts

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

    /// Return whether this substitution should also switch keyboard layout to the target language.
    func shouldSwitchLayout(for source: String, pair: LayoutPair) -> Bool {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        let lower = source.lowercased()
        if let direct = switchLayouts[pair.key]?[source] ?? switchLayouts[pair.key]?[lower] {
            return direct
        }
        if let inverse = switchLayouts[inverseKey]?[source] ?? switchLayouts[inverseKey]?[lower] {
            return inverse
        }
        return false
    }

    /// Save a substitution for a language pair. Overwrites any previous value
    /// for the same `source` in either direction of the pair.
    func set(
        source: String,
        target: String,
        switchLayout: Bool = false,
        for pair: LayoutPair
    ) {
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

        switchLayouts[inverseKey]?.removeValue(forKey: source)
        var currentSwitches = switchLayouts[pair.key] ?? [:]
        currentSwitches[source] = switchLayout
        switchLayouts[pair.key] = currentSwitches

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

        switchLayouts[pair.key]?.removeValue(forKey: source)
        switchLayouts[inverseKey]?.removeValue(forKey: source)

        if changed {
            persist()
        }
    }

    /// Remove all substitutions for a language pair (both directions).
    func removeAll(for pair: LayoutPair) {
        let inverseKey = LayoutPair(from: pair.to, to: pair.from).key
        let removedDirect = mappings.removeValue(forKey: pair.key) != nil
        let removedInverse = mappings.removeValue(forKey: inverseKey) != nil
        switchLayouts.removeValue(forKey: pair.key)
        switchLayouts.removeValue(forKey: inverseKey)
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
            let shouldSwitch = shouldSwitchLayout(for: direct.original, pair: pair)
            return WordMatchResult(
                original: direct.original,
                replacement: direct.replacement,
                targetLayout: shouldSwitch ? pair.to : nil
            )
        }
        let inversePair = LayoutPair(from: pair.to, to: pair.from)
        if let inverse = WordMatcher.findMatch(word: word, in: entries(for: inversePair)) {
            let shouldSwitch = shouldSwitchLayout(for: inverse.original, pair: inversePair)
            return WordMatchResult(
                original: inverse.original,
                replacement: inverse.replacement,
                targetLayout: shouldSwitch ? inversePair.to : nil
            )
        }
        // Iterate keys sorted: the JSON object has no order, so without this
        // an ambiguous fallback match could flip between launches.
        for key in mappings.keys.sorted() where key != pair.key && key != inversePair.key {
            guard let dict = mappings[key] else { continue }
            if let fallback = WordMatcher.findMatch(word: word, in: dict) {
                let parts = key.split(separator: "|")
                let fallbackTarget = (parts.count == 2) ? String(parts[1]) : nil
                let pairFromKey = LayoutPair(from: String(parts.first ?? ""), to: fallbackTarget ?? "")
                let shouldSwitch = shouldSwitchLayout(for: fallback.original, pair: pairFromKey)
                return WordMatchResult(
                    original: fallback.original,
                    replacement: fallback.replacement,
                    targetLayout: shouldSwitch ? fallbackTarget : nil
                )
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
        if let switchData = UserDefaults.standard.data(forKey: switchLayoutsDefaultsKey),
           let decodedSwitches = try? JSONDecoder().decode([String: [String: Bool]].self, from: switchData) {
            switchLayouts = Self.migratePairKeys(decodedSwitches) { _, new in new }
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("🗂 [WordMapperStore] No word mappings file found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let rawMappings = try decoder.decode([String: [String: String]].self, from: data)
            // Merge sources written under different spellings of the same pair.
            mappings = Self.migratePairKeys(rawMappings) { old, new in old.merging(new) { _, n in n } }
            let total = mappings.values.reduce(0) { $0 + $1.count }
            print("🗂 [WordMapperStore] Loaded \(total) word mapping(s) from disk")
        } catch {
            print("⚠️ [WordMapperStore] Failed to load word mappings: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let snapshot = mappings
        let switchesSnapshot = switchLayouts
        if let switchData = try? JSONEncoder().encode(switchesSnapshot) {
            UserDefaults.standard.set(switchData, forKey: switchLayoutsDefaultsKey)
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

extension WordMapperStore {
    /// Normalize the top-level `"from|to"` keys of a persisted dictionary so
    /// entries saved under the old raw-name scheme keep matching. Collisions
    /// (e.g. `"Russian – PC|ABC"` vs `"Russian - PC|ABC"`) are merged.
    static func migratePairKeys<T>(_ dict: [String: T], merge: (T, T) -> T) -> [String: T] {
        var migrated: [String: T] = [:]
        for (key, value) in dict {
            let newKey = LayoutPair.migrateKey(key)
            if let existing = migrated[newKey] {
                migrated[newKey] = merge(existing, value)
            } else {
                migrated[newKey] = value
            }
        }
        return migrated
    }
}
