import Foundation
import Combine
import AppKit

/// Manages persistence of `LayoutMapperPreset` instances.
/// Stores presets in `~/Library/Application Support/EzSwitch/presets.json`.
final class MapperStore: ObservableObject {
    static let shared = MapperStore()

    /// Published list of all presets
    @Published private(set) var presets: [LayoutMapperPreset] = []

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.ezswitch.mapperstore", qos: .userInitiated)
    private var didAttemptSeed = false
    /// Pending debounced disk write, cancelled and rescheduled on each change.
    private var persistWork: DispatchWorkItem?

    private init() {
        loadFromDisk()
    }

    /// Defer auto-seeding until the first actual read/write.
    /// This avoids doing UCKeyTranslate work during app launch
    /// for users who already have presets or don't use mappers yet.
    private func ensureSeeded() {
        guard !didAttemptSeed else { return }
        didAttemptSeed = true
        if presets.isEmpty {
            seedAutoPreset()
        }
    }

    // MARK: - File Paths

    /// Application Support directory
    private var appSupportDirectory: URL {
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let ezswitchURL = url.appendingPathComponent(Constants.FilePath.appSupportFolder, isDirectory: true)
            if !fileManager.fileExists(atPath: ezswitchURL.path) {
                try? fileManager.createDirectory(at: ezswitchURL, withIntermediateDirectories: true)
            }
            return ezswitchURL
        }
        // Fallback to ~/Library/Application Support
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/\(Constants.FilePath.appSupportFolder)", isDirectory: true)
    }

    /// JSON file with presets
    private var presetsFileURL: URL {
        return appSupportDirectory.appendingPathComponent(Constants.FilePath.presetsFile)
    }

    // MARK: - Public API

    /// Get all presets for a specific layout pair (in either order)
    func presets(for pair: LayoutPair) -> [LayoutMapperPreset] {
        ensureSeeded()
        let inverse = LayoutPair(from: pair.to, to: pair.from)
        return presets.filter { $0.pair == pair || $0.pair == inverse }
    }

    /// Get a preset by ID
    func preset(byID id: String) -> LayoutMapperPreset? {
        ensureSeeded()
        return presets.first(where: { $0.id == id })
    }

    /// Save (insert or update) a preset
    func save(_ preset: LayoutMapperPreset) {
        ensureSeeded()
        var updated = preset
        updated.updatedAt = Date()

        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = updated
        } else {
            presets.append(updated)
        }
        persist()
    }

    /// Delete a preset by ID
    func delete(id: String) {
        ensureSeeded()
        presets.removeAll(where: { $0.id == id })
        persist()
    }

    /// Create a new preset for a pair, with optional auto-generated mapping
    @discardableResult
    func createPreset(
        name: String,
        from: String,
        to: String,
        mapping: [String: String] = [:]
    ) -> LayoutMapperPreset {
        ensureSeeded()
        let preset = LayoutMapperPreset(
            name: name,
            fromLayout: from,
            toLayout: to,
            mapping: mapping
        )
        presets.append(preset)
        persist()
        return preset
    }

    // MARK: - Persistence

    /// Load presets from JSON file
    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: presetsFileURL.path) else {
            print("🗂 [MapperStore] No presets file found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([LayoutMapperPreset].self, from: data)
            // Deduplicate identical "(auto)" presets created by previous versions
            var seenAutoNames: Set<String> = []
            var deduplicated: [LayoutMapperPreset] = []
            for p in loaded {
                if p.name.hasSuffix("(auto)") {
                    // Normalize like `LayoutPair.key` so duplicates written with
                    // different dash styles/cases are recognized as identical.
                    let key = "\(LayoutPair.normalized(p.fromLayout))|\(LayoutPair.normalized(p.toLayout))|\(p.name)"
                    if seenAutoNames.contains(key) { continue }
                    seenAutoNames.insert(key)
                }
                deduplicated.append(p)
            }
            presets = deduplicated
            if deduplicated.count != loaded.count {
                persist()
            }
            print("🗂 [MapperStore] Loaded \(presets.count) preset(s) from disk")
        } catch {
            print("⚠️ [MapperStore] Failed to load presets: \(error.localizedDescription)")
        }
    }

    /// Save presets to JSON file.
    ///
    /// The editor calls `save(_:)` on every keystroke, so writing straight
    /// away would encode and rewrite the whole file per character typed.
    /// Instead the write is coalesced: rapid changes collapse into a single
    /// disk write a moment after typing pauses.
    private func persist() {
        persistWork?.cancel()
        let snapshot = presets
        let work = DispatchWorkItem { [weak self] in
            self?.writePresets(snapshot)
        }
        persistWork = work
        queue.asyncAfter(deadline: .now() + Constants.Timing.persistDebounceSec, execute: work)
    }

    /// Encode `snapshot` and write it to disk. Runs on `queue`.
    private func writePresets(_ snapshot: [LayoutMapperPreset]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: presetsFileURL, options: .atomic)
            print("🗂 [MapperStore] Saved \(snapshot.count) preset(s) to disk")
        } catch {
            print("⚠️ [MapperStore] Failed to save presets: \(error.localizedDescription)")
        }
    }

    /// Flush any pending debounced write immediately, synchronously.
    /// Call before the values are read by another process, or on termination,
    /// so a debounced write is not lost with the process.
    func flush() {
        guard let work = persistWork, !work.isCancelled else {
            persistWork = nil
            return
        }
        work.cancel()
        persistWork = nil
        // Read the live list here (main-confined) and write synchronously so
        // the data is on disk by the time this returns.
        let snapshot = presets
        queue.sync { writePresets(snapshot) }
    }

    // MARK: - Seed

    /// On first launch, auto-generate a preset for the user's current
    /// left/right language pair so transformation works out of the box for
    /// any installed layout — no hardcoded mapping needed.
    private func seedAutoPreset() {
        let settings = SettingsManager.shared
        let from = settings.leftCommandLanguage
        let to = settings.rightCommandLanguage

        // Skip if either side is "None" or both are the same — nothing useful
        // to map. The user can still build a preset manually later.
        guard !from.isEmpty, !to.isEmpty,
              from != to,
              from != Constants.Default.noneLanguage, to != Constants.Default.noneLanguage else {
            print("🌱 [MapperStore] Skipping auto-seed: invalid pair (\(from) → \(to))")
            return
        }

        let mapping = KeyboardLayoutUtility.buildMapping(fromLayout: from, toLayout: to)
        guard !mapping.isEmpty else {
            print("🌱 [MapperStore] Skipping auto-seed: UCKeyTranslate returned empty mapping for \(from) → \(to)")
            return
        }

        let preset = LayoutMapperPreset(
            name: "\(from) ↔ \(to) (auto)",
            fromLayout: from,
            toLayout: to,
            mapping: mapping
        )
        presets.append(preset)
        settings.setSelectedPresetId(preset.id, for: from, to)
        persist()
        print("🌱 [MapperStore] Auto-seeded preset for \(from) ↔ \(to) with \(mapping.count) entries")
    }
}
