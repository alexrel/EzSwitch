import Foundation

/// Immutable rules and preferences for one explicit correction, captured on main.
struct TransformSnapshot: Equatable {
    let primaryLanguages: [String]
    let activePresets: [LayoutMapperPreset]
    let switchLayoutAfterTransform: Bool

    init(presets: [LayoutMapperPreset], selectedPresetIDs: [String: String],
         primaryLanguages: [String], switchLayoutAfterTransform: Bool) {
        self.primaryLanguages = primaryLanguages.filter { !$0.isEmpty && $0 != Constants.Default.noneLanguage }
        self.switchLayoutAfterTransform = switchLayoutAfterTransform
        var seenPairs = Set<Set<String>>()
        var active: [LayoutMapperPreset] = []
        for preset in presets {
            let pair = preset.pair
            let inverse = LayoutPair(from: pair.to, to: pair.from)
            let key = Set([LayoutPair.normalized(pair.from), LayoutPair.normalized(pair.to)])
            guard seenPairs.insert(key).inserted else { continue }
            let selectedID = selectedPresetIDs[pair.key] ?? selectedPresetIDs[inverse.key]
            let candidates = presets.filter { $0.pair == pair || $0.pair == inverse }
            active.append(candidates.first(where: { $0.id == selectedID }) ?? preset)
        }
        activePresets = active
    }

    /// The same snapshot supplies every hop, including reverse and bridge rules.
    func transform(text: String, from: String, to: String) -> String? {
        transform(text: text, from: from, to: to, depth: 0)
    }

    private func transform(text: String, from: String, to: String, depth: Int) -> String? {
        guard depth < 3 else { return nil }
        if LayoutPair.namesMatch(from, to) { return text }
        let pair = LayoutPair(from: from, to: to)
        let inverse = LayoutPair(from: to, to: from)
        if let preset = activePresets.first(where: { $0.pair == pair || $0.pair == inverse }) {
            let result = preset.apply(text, from: from)
            if result != text { return result }
        }

        for preset in activePresets {
            let bridge: String
            if LayoutPair.namesMatch(preset.fromLayout, from) { bridge = preset.toLayout }
            else if LayoutPair.namesMatch(preset.toLayout, from) { bridge = preset.fromLayout }
            else { continue }
            guard !LayoutPair.namesMatch(bridge, from), !LayoutPair.namesMatch(bridge, to) else { continue }
            let secondPair = LayoutPair(from: bridge, to: to)
            let secondInverse = LayoutPair(from: to, to: bridge)
            guard activePresets.contains(where: { $0.pair == secondPair || $0.pair == secondInverse }) else { continue }
            if let intermediate = transform(text: text, from: from, to: bridge, depth: depth + 1),
               intermediate != text,
               let result = transform(text: intermediate, from: bridge, to: to, depth: depth + 1) {
                return result
            }
        }
        return nil
    }
}
