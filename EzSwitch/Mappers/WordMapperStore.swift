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

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.ezswitch.wordmapperstore", qos: .userInitiated)

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// All source→target entries for a given direction.
    func entries(for pair: LayoutPair) -> [String: String] {
        return mappings[pair.key] ?? [:]
    }

    /// Save a single one-way substitution. Overwrites any previous value for
    /// the same `source` in the same direction.
    func set(source: String, target: String, for pair: LayoutPair) {
        guard !source.isEmpty, !target.isEmpty else { return }
        var current = mappings[pair.key] ?? [:]
        current[source] = target
        mappings[pair.key] = current
        persist()
    }

    /// Remove a single substitution.
    func remove(source: String, for pair: LayoutPair) {
        guard var current = mappings[pair.key] else { return }
        guard current.removeValue(forKey: source) != nil else { return }
        if current.isEmpty {
            mappings.removeValue(forKey: pair.key)
        } else {
            mappings[pair.key] = current
        }
        persist()
    }

    /// Remove all substitutions for a direction.
    func removeAll(for pair: LayoutPair) {
        guard mappings.removeValue(forKey: pair.key) != nil else { return }
        persist()
    }

    /// Look up a substitution for a typed word in a given direction.
    func findMatch(word: String, pair: LayoutPair) -> WordMatchResult? {
        return WordMatcher.findMatch(word: word, in: entries(for: pair))
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
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(self.mappings)
                try data.write(to: self.fileURL, options: .atomic)
                let total = self.mappings.values.reduce(0) { $0 + $1.count }
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
